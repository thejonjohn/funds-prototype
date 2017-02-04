require 'date'
require 'chronic'

class FundsApp < Sinatra::Application

  get '/' do
    redirect url('balances')
  end

  get '/balances/?' do
    if params[:start_date]
      session[:start_date] = params[:start_date]
    end
    if params[:end_date]
      session[:end_date] = params[:end_date]
    end
    if params[:account_filter]
      session[:account_filter] = params[:account_filter]
    end
    end_date, start_date = [session[:end_date], session[:start_date]].map do |the_date|
      if the_date
        if the_date.empty?
          the_date = nil
        else
          the_date = Date.parse(Chronic.parse(the_date).to_s)
        end
      end
      the_date
    end


    @funds_info = funds_info(end_date: end_date, start_date: start_date, account_filter: session[:account_filter])
    haml :balances
  end

  get '/register/?' do
    if params[:start_date]
      session[:start_date] = params[:start_date]
    end
    if params[:end_date]
      session[:end_date] = params[:end_date]
    end
    if params[:account_filter]
      session[:account_filter] = params[:account_filter]
    end
    end_date, start_date = [session[:end_date], session[:start_date]].map do |the_date|
      if the_date
        if the_date.empty?
          the_date = nil
        else
          the_date = Date.parse(Chronic.parse(the_date).to_s)
        end
      end
      the_date
    end

    @funds_info = funds_info(end_date: end_date, start_date: start_date, account_filter: session[:account_filter])
    haml :register
  end

end
