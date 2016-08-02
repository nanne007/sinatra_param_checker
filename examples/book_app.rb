require 'json'
require 'sinatra/base'
require 'sinatra/param_checker'

class BookApp < Sinatra::Base
  register Sinatra::ParamChecker

  params '/books', methods: [:post] do
    required 'name', type: String
    optional 'author', type: String, default: 'unknown'
    required 'publish_date', type: Date
  end
  post '/books' do
    {
      name: params[:name],
      author: params[:author],
      publish_date: params[:publish_date]
    }.to_json
  end

  run!
end
