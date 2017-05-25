Puppet::Type.newtype(:mongodb_user) do
  @doc = 'Manage a MongoDB user. This includes management of users password as well as privileges.'

  ensurable

  def initialize(*args)
    super
    # Sort roles array before comparison.
    # Munged values safe to sort by db and role
    Puppet.debug(self[:roles])
    self[:roles] = Array(self[:roles]).sort! { |a, b| [a['db'], a['role' ]] <=> [b['db'], b['role']] }
  end

  newparam(:name, :namevar=>true) do
    desc "The name of the resource."
  end

  newproperty(:username) do
    desc "The name of the user."
    defaultto { @resource[:name] }
  end

  newproperty(:database) do
    desc "The user's target database."
    defaultto do
      fail("Parameter 'database' must be set") if provider.database == :absent
    end
    newvalues(/^\w+$/)
  end

  newparam(:tries) do
    desc "The maximum amount of two second tries to wait MongoDB startup."
    defaultto 10
    newvalues(/^\d+$/)
    munge do |value|
      Integer(value)
    end
  end

  newproperty(:roles, :array_matching => :all) do
    desc "The user's roles."
    defaultto ['dbAdmin']
    # newvalue(/^\w+$/)
   
    validate do |value|
      klass = value.class
      val_regex = /^\w+$/
      case klass.to_s
      when "String"
        return value if value.match(val_regex)
        raise ArgumentError,
          "Roles defined with Strings must be single words"
      when "Hash"
        return value if ((value.key?('db') and value.key?('role')) \
                         and (value['db'].match(val_regex) and value['role'].match(val_regex))) 
        raise ArgumentError,
          "roles defined with hashes must contain valid values for keys 'db' and 'role'"
      else
        raise ArgumentError,
          "Roles must be String or Hash"
      end	
    end 

    munge do |value|
      if value.class == String
        Puppet.debug("We gotta munge this #{value}")
        { "role" => value, "db" => @resource[:database] }
      else
        value
      end
    end	

    # Pretty output for arrays.
    def should_to_s(value)
      value.inspect
    end

    def is_to_s(value)
      value.inspect
    end
  end

  newproperty(:password_hash) do
    desc "The password hash of the user. Use mongodb_password() for creating hash."
    defaultto do
      fail("Property 'password_hash' must be set. Use mongodb_password() for creating hash.") if provider.database == :absent
    end
    newvalue(/^\w+$/)
  end

  autorequire(:package) do
    'mongodb_client'
  end

  autorequire(:service) do
    'mongodb'
  end
end
