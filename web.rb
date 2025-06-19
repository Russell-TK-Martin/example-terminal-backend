puts ">> Starting Sinatra backend..."

require 'sinatra'
require 'stripe'
require 'dotenv'
require 'json'
require 'sinatra/cross_origin'

# CORS config for browser-based clients
configure do
  enable :cross_origin
end

# ✅ Required for Render deployment
set :port, ENV['PORT'] || 4567
set :bind, '0.0.0.0'

before do
  response.headers['Access-Control-Allow-Origin'] = '*'
end

options "*" do
  response.headers["Allow"] = "GET, POST, OPTIONS"
  response.headers["Access-Control-Allow-Headers"] = "Authorization, Content-Type, Accept, X-User-Email, X-Auth-Token"
  response.headers["Access-Control-Allow-Origin"] = "*"
  200
end

Dotenv.load
Stripe.api_key = ENV['STRIPE_ENV'] == 'production' ? ENV['STRIPE_SECRET_KEY'] : ENV['STRIPE_TEST_SECRET_KEY']
Stripe.api_version = '2020-03-02'

def log_info(message)
  puts "\n" + message + "\n\n"
  return message
end

def validateApiKey
  if Stripe.api_key.nil? || Stripe.api_key.empty?
    return "Error: you provided an empty secret key. Please provide your test mode secret key."
  end
  if Stripe.api_key.start_with?('pk')
    return "Error: you used a publishable key. Use your test mode *secret* key."
  end
  if Stripe.api_key.start_with?('sk_live')
    return "Error: you're using a live key in test mode. Use your test secret key."
  end
  return nil
end

get '/' do
  status 200
  send_file 'index.html'
end

# ✅ Create connection token
post '/connection_token' do
  puts ">> /connection_token requested"
  validationError = validateApiKey
  if validationError
    status 400
    return log_info(validationError)
  end

  begin
    token = Stripe::Terminal::ConnectionToken.create
    status 200
    content_type :json
    return { secret: token.secret }.to_json
  rescue Stripe::StripeError => e
    status 402
    return log_info("ConnectionToken error: #{e.message}")
  end
end

# ✅ Create payment intent
post '/create_payment_intent' do
  puts ">> /create_payment_intent called"
  validationError = validateApiKey
  if validationError
    status 400
    return log_info(validationError)
  end

  begin
    payment_intent = Stripe::PaymentIntent.create(
      payment_method_types: params[:payment_method_types] || ['card_present'],
      capture_method: 'automatic',
      amount: params[:amount],
      currency: params[:currency] || 'usd',
      description: params[:description] || 'Example PaymentIntent',
      payment_method_options: params[:payment_method_options] || {},
      receipt_email: params[:receipt_email]
    )

    log_info("PaymentIntent created: #{payment_intent.id}")
    status 200
    content_type :json
    return { intent: payment_intent.id, secret: payment_intent.client_secret }.to_json

  rescue Stripe::StripeError => e
    status 402
    return log_info("PaymentIntent creation failed: #{e.message}")
  end
end

# ✅ Capture payment intent
post '/capture_payment_intent' do
  puts ">> /capture_payment_intent called"
  begin
    id = params["payment_intent_id"]
    payment_intent = if params["amount_to_capture"]
      Stripe::PaymentIntent.capture(id, amount_to_capture: params["amount_to_capture"])
    else
      Stripe::PaymentIntent.capture(id)
    end

    log_info("Captured PaymentIntent: #{id}")
    status 200
    return { intent: payment_intent.id, secret: payment_intent.client_secret }.to_json

  rescue Stripe::StripeError => e
    status 402
    return log_info("Capture failed: #{e.message}")
  end
end

# ✅ Cancel payment intent
post '/cancel_payment_intent' do
  puts ">> /cancel_payment_intent called"
  begin
    id = params["payment_intent_id"]
    payment_intent = Stripe::PaymentIntent.cancel(id)
    log_info("Canceled PaymentIntent: #{id}")
    status 200
    return { intent: payment_intent.id, secret: payment_intent.client_secret }.to_json

  rescue Stripe::StripeError => e
    status 402
    return log_info("Cancel failed: #{e.message}")
  end
end

