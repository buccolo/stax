require 'tempfile'
require 'awful/keypair'
require 'awful/param'

module Stax
  module Keypair
    def self.included(thor)
      thor.class_eval do

        no_commands do
          def key_pair_name
            @_key_pair_name ||= stack_name
          end

          ## parameter store name to store private key
          def key_pair_store_name
            "#{key_pair_name}.key_pair"
          end

          def key_pair_describe
            keypair(:ls, [key_pair_name], long: true)
          rescue Aws::EC2::Errors::InvalidKeyPairNotFound => e
            warn(e.message)
          end

          ## create a new key pair and return private key
          def key_pair_create
            keypair(:create, [key_pair_name], quiet: true).key_material
          rescue Aws::EC2::Errors::InvalidKeyPairDuplicate => e
            warn(e.message)
            nil
          end

          ## create a key and store it in parameter store
          def key_pair_store
            key = key_pair_create or return
            param(:put, [key_pair_store_name], value: key, type: 'SecureString', key_id: try(:kms_id), overwrite: true)
          end

          ## get private key from store and write to a tempfile for ssh to find; return file object
          def key_pair_get
            Tempfile.new(stack_name).tap do |file|
              key = param(:get, [key_pair_store_name], decrypt: true, quiet: true).first
              File.chmod(0400, file.path) # ssh needs this mode
              file.write(key.value)
              file.close
            end
          end

          ## delete the key pair and the parameter store
          def key_pair_delete
            keypair(:delete, [key_pair_name], yes: true)
            param(:delete, [key_pair_store_name], yes: true)
          rescue Aws::SSM::Errors::ParameterNotFound
            warn("Parameter #{key_pair_store_name} does not exist")
          end
        end

        desc 'key', 'key pair tasks'
        method_option :create, type: :boolean, default: false, desc: 'create a new key pair'
        method_option :delete, type: :boolean, default: false, desc: 'delete key pair'
        def key
          if options[:create]
            key_pair_store
          elsif options[:delete]
            key_pair_delete
          else
            key_pair_describe
          end
        end

      end
    end
  end
end