require File.expand_path(File.join(File.dirname(__FILE__), '..','..', '..', 'puppet_x', 'mongodb', 'crypt', 'password_validator.rb' ))
require File.expand_path(File.join(File.dirname(__FILE__), '..', 'mongodb'))
Puppet::Type.type(:mongodb_user).provide(:mongodb, :parent => Puppet::Provider::Mongodb) do

  desc "Manage users for a MongoDB database."

  defaultfor :kernel => 'Linux'

  def self.instances
    require 'json'

    if db_ismaster
      if mongo_24?
        dbs = JSON.parse mongo_eval('printjson(db.getMongo().getDBs()["databases"].map(function(db){return db["name"]}))') || 'admin'

        allusers = []

        dbs.each do |db|
          users = JSON.parse mongo_eval('printjson(db.system.users.find().toArray())', db)

          allusers += users.collect do |user|
              new(:name          => user['_id'],
                  :ensure        => :present,
                  :username      => user['user'],
                  :database      => db,
                  :roles         => user['roles'].sort,
                  :password_hash => user['pwd'])
          end
        end
        return allusers
      else
        # Add projection to avoid some bin data
        users = JSON.parse mongo_eval('printjson(db.system.users.find({},{"_id": 1, "roles": 1, "user": 1, "db": 1}).toArray())')
        users.collect do |user|
            Puppet.debug("Roles for #{user['user']}: #{ user['roles']}")
            new(:name          => user['_id'],
                :ensure        => :present,
                :username      => user['user'],
                :database      => user['db'],
                :roles         => from_roles(user['roles']),
                :password_hash => '')
        end
      end
    else
      Puppet.warning 'User info is available only from master host'
      return []
    end
  end

  # Assign prefetched users based on username and database, not on id and name
  def self.prefetch(resources)
    users = instances
    resources.each do |name, resource|
      if provider = users.find { |user| user.username == resource[:username] and user.database == resource[:database] }
        # populate @property_hash with the password_hash from the resource
        # so we can use it then to check if it has to be updated
        provider.set(:password_hash => resource[:password_hash])        
        resources[name].provider = provider
      end
    end
  end

  mk_resource_methods

  def create
    if db_ismaster
      if mongo_24?
        user = {
          :user => @resource[:username],
          :pwd => @resource[:password_hash],
          :roles => @resource[:roles]
        }

        mongo_eval("db.addUser(#{user.to_json})", @resource[:database])
      else
        cmd_json=<<-EOS.gsub(/^\s*/, '').gsub(/$\n/, '')
        {
          "createUser": "#{@resource[:username]}",
          "pwd": "#{@resource[:password_hash]}",
          "customData": {"createdBy": "Puppet Mongodb_user['#{@resource[:name]}']"},
          "roles": #{@resource[:roles].to_json},
          "digestPassword": false
        }
        EOS

        mongo_eval("db.runCommand(#{cmd_json})", @resource[:database])
      end

      @property_hash[:ensure] = :present
      @property_hash[:username] = @resource[:username]
      @property_hash[:database] = @resource[:database]
      @property_hash[:password_hash] = ''
      @property_hash[:roles] = @resource[:roles]

      exists? ? (return true) : (return false)
    else
      Puppet.warning 'User creation is available only from master host'
    end
  end


  def destroy
    if db_ismaster
      if mongo_24?
        mongo_eval("db.removeUser('#{@resource[:username]}')")
      else
        mongo_eval("db.dropUser('#{@resource[:username]}')")
      end
    else
      mongo_eval("db.dropUser('#{@resource[:username]}')")
    end
  end

  def exists?
    !(@property_hash[:ensure] == :absent or @property_hash[:ensure].nil?)
  end

  def password_hash

    query_filter=<<-EOS.gsub(/^\s*/, '').gsub(/$\n/, '')
    {
      "user": "#{@property_hash[:username]}",
      "db": "#{@property_hash[:database]}"
    }
    EOS

    query_proj=<<-EOS.gsub(/^\s*/, '').gsub(/$\n/, '')
    {
      "credentials": 1
    }
    EOS

    raw_users = mongo_eval(
       "printjson(db.system.users.find( #{query_filter}, #{query_proj} ).toArray())")

    return '' if raw_users.nil?
	
    users = JSON.parse raw_users

    # Process the credentials
    creds = users[0]['credentials']
    if creds.key?('MONGODB-CR')
      return creds['MONGODB-CR'] 
    end

    if creds.key?('SCRAM-SHA-1')
      validator = PuppetX::Mongodb::Crypt::PasswordValidator.new
      return '' unless validator.validate(creds, @property_hash[:password_hash])
      @property_hash[:password_hash]
    end
  end	

  def password_hash=(value)
    if db_ismaster
      cmd_json=<<-EOS.gsub(/^\s*/, '').gsub(/$\n/, '')
      {
          "updateUser": "#{@resource[:username]}",
          "pwd": "#{@resource[:password_hash]}",
          "digestPassword": false
      }
      EOS
      mongo_eval("db.runCommand(#{cmd_json})", @resource[:database])
    else
      Puppet.warning 'User password operations are available only from master host'
    end
  end

  def roles=(roles)
    Puppet.debug("Target roles for #{@resource[:username]}: #{roles}")     
    Puppet.debug("Resource roles for #{@resource[:username]}: #{@resource[:roles]}")     
    if db_ismaster
      if mongo_24?
        mongo_eval("db.system.users.update({user:'#{@resource[:username]}'}, { $set: {roles: #{@resource[:roles].to_json}}})")
      else
        grant = roles-@property_hash[:roles]
        if grant.length > 0
          Puppet.debug("Granting roles to: #{@resource[:username]}. Roles granted: #{grant}")     
          mongo_eval("db.getSiblingDB('#{@resource[:database]}').grantRolesToUser('#{@resource[:username]}', #{grant.to_json})")
        end

        revoke = @property_hash[:roles]-roles
        if revoke.length > 0
          Puppet.debug("Revoking roles from: #{@resource[:username]}. Roles revoked #{revoke}")     
          mongo_eval("db.getSiblingDB('#{@resource[:database]}').revokeRolesFromUser('#{@resource[:username]}', #{revoke.to_json})")
        end
      end
    else
      Puppet.warning 'User roles operations are available only from master host'
    end
  end

  private

  def self.from_roles(roles)
    #roles.map do |entry|
    #    Puppet.debug("from_roles function, processing entry #{entry}")
    #    if entry['db'] == db
    #       # entry['role']
    #       entry
    #   else
    #        # "#{entry['role']}@#{entry['db']}"
    #        entry
    #    end
    #end.sort { |a, b| [a['db'], a['role' ]] <=> [b['db'], b['role']] }
    roles.sort { |a, b| [a['db'], a['role' ]] <=> [b['db'], b['role']] }
  end
end
