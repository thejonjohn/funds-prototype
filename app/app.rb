require 'sinatra'

require_relative 'routes/init'
require_relative 'helpers/init'
require_relative 'lib/app_config'

class FundsApp < Sinatra::Application

  set :root, File.dirname(__FILE__)
  enable :sessions

end
