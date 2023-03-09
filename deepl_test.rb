require_relative 'deepl_trans'
require 'active_support'
require 'active_support/core_ext'

def parse_env(envs)
  params = {}.with_indifferent_access
  envs.each do |env|
    k, v = env.split('=')
    params[k] = v
  end
  params
end

class Net::HTTP
  alias create initialize

  def initialize(*args)
    create(*args)
    # self.set_debug_output $stderr
    # $stderr.sync = true
  end
end

config = YAML.load(File.open('docker-compose.yml')).with_indifferent_access
environment = parse_env(config[:services]['discord-ttsbot1'][:environment])

DEEPL_AUTH_KEY = environment[:DEEPL_AUTH_KEY]
DEEPL_PAID = !environment[:DEEPL_PAID].nil?
puts "PAID STATUS: #{DEEPL_PAID}"

deepl = Trans.new(DEEPL_AUTH_KEY, DEEPL_PAID)
message = 'this is test. ignore me.'
puts deepl.trans(message)
