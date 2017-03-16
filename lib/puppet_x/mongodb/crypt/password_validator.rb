require 'digest/md5'
require 'digest/sha1'
require 'openssl'
require 'base64' 

module PuppetX
  module Mongodb
    module Crypt
      class PasswordValidator

        DIGEST = OpenSSL::Digest::SHA1.new.freeze
        CLIENT_KEY = 'Client Key'.freeze
        SERVER_KEY = 'Server Key'.freeze


        def validate(creds, password_hash)
          salt = creds['SCRAM-SHA-1']['salt']
          iters = creds['SCRAM-SHA-1']['iterationCount']

          saltedPassword = key_derive(password_hash,
                                      salt,
                                      iters,
                                      DIGEST)
          clientKey = hmac(saltedPassword, CLIENT_KEY)
          storedKey = Base64.strict_encode64(h(clientKey))
          serverKey = Base64.strict_encode64(hmac(saltedPassword, SERVER_KEY))
          (storedKey == creds['SCRAM-SHA-1']['storedKey']) && \
          (serverKey == creds['SCRAM-SHA-1']['serverKey'])	

        end

        private

        def hash_user_password(user, pwd)
         Digest::MD5.hexdigest("#{user}:mongo:#{pwd}")
        end

        def hmac(data, key)
          OpenSSL::HMAC.digest(DIGEST, data, key)
        end

        def key_derive(data, salt, iterations, digest)
          OpenSSL::PKCS5.pbkdf2_hmac_sha1(
            data,
            Base64.strict_decode64(salt),
            iterations,
            digest.size
          )
        end

        def h(string)
          DIGEST.digest(string)
        end

        def salted_password(hashed_password)
          hi(hashed_password)
        end

        def stored_key(key)
          h(key)
        end
      end
    end
  end
end
        
# class Puppet::PuppetX::Mongodb::Crypt::PasswordValidator


