Rails.application.routes.draw do
  root 'proxy#show'
  get 'proxy#send_data', to: 'proxy#show'
  get '/deck', to: 'proxy#new'
  get '/deck/:id', to: 'proxy#new'
  get '/card', to: 'proxy#new'
  get '/pack', to: 'proxy#new'
  post '/netrunner', to: 'proxy#netrunner'
  post '/netrunner/pack', to: 'proxy#netrunner_pack'
  # For details on the DSL available within this file, see http://guides.rubyonrails.org/routing.html
end
