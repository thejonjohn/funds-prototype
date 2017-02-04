require_relative '../lib/main_helpers.rb'

class FundsApp < Sinatra::Application

  helpers do
    include MainFundsHelpers
  end

end
