require 'yaml'

class AppConfig

  def self.config
    config_file = File.join(File.dirname(File.dirname(File.expand_path(__FILE__))), 'config', 'config.yml')
    key = self.production? ? 'production' : 'development'
    yml = YAML::load(File.read(config_file))
    raise "key '#{key}' not found in #{config_file}" if yml.nil? || yml[key].nil?
    return yml[key]
  end

  def self.production?
    return ENV['RACK_ENV'] == "production"
  end

  def self.development?
    return !self.production?
  end

  def self.[](key)
    return self.config[key.to_s]
  end

end
