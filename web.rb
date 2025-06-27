puts ">> Starting Sinatra backend..."

require 'sinatra'
require 'stripe'
require 'dotenv'
require 'json'
require 'sinatra/cross_origin'

# --- CORS Config for browser clients ---
configure do
  enable :cross_origin
end

# --- Render-compatible settings ---
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

# --- Load Environment Variables ---
Dotenv.load

# --- Logging: Print key status for debug ---
puts ">> ENV['STRIPE_ENV']: #{ENV['STRIPE_ENV'] || '(not set)'}"
puts ">> ENV['STRIPE_TEST_SECRET_KEY']: #{ENV['STRIPE_TEST_SECRET_KEY'] ? '[loaded]' : '(empty)'}"
puts ">> ENV['STRIPE_SECRET_KEY']: #{ENV['STRIPE_SECRET_KEY'] ? '[loaded]' : '(empty)'}"

# --- Stripe Setup ---
Stripe.api_key = ENV['STRIPE_SECRET_KEY']

# --- Helpers ---
def log_info(message)
  puts "\n#{message}\n\n"
  message
end

def validateApiKey
  if Stripe.api_key.nil? || Stripe.api_key.empty?
    return "Error: you provided an empty secret key. Please provide your test mode secret key."
  end
  if Stripe.api_key.start_with?('pk')
    return "Error: you used a publishable key. Use your test mode *secret* key."
  end
  nil
end

# --- Routes ---

get '/' do
  status 200
  send_file 'index.html'
end

# ✅ Step 1: Provide connection token
post '/connection_token' do
  puts ">> /connection_token requested"

  if (error = validateApiKey)
    status 400
    return log_info(error)
  end

  begin
    token = Stripe::Terminal::ConnectionToken.create
    log_info("✅ Token created: #{token.id}")
    content_type :json
    status 200
    { secret: token.secret }.to_json
  rescue Stripe::StripeError => e
    status 402
    log_info("❌ ConnectionToken error: #{e.message}")
  end
end

# ✅ Step 2: Create payment intent
post '/create_payment_intent' do
  puts ">> /create_payment_intent called"
  puts ">>> DEBUG: capture_method = automatic"
  puts ">>> Incoming params: #{params.inspect}"

  if (error = validateApiKey)
    status 400
    return log_info(error)
  end

  begin
    payment_intent = Stripe::PaymentIntent.create(
      payment_method_types: ['card_present'],
      capture_method: 'automatic',
      amount: params[:amount],
      currency: params[:currency] || 'eur',
      description: params[:description] || 'Terminal Transaction',
      receipt_email: params[:receipt_email]
    )

    log_info("✅ PaymentIntent created: #{payment_intent.id}")
    content_type :json
    status 200
    { intent: payment_intent.id, secret: payment_intent.client_secret }.to_json
  rescue Stripe::StripeError => e
    status 402
    log_info("❌ PaymentIntent creation failed: #{e.message}")
  end
end

# ✅ Capture payment intent (if using manual capture)
post '/capture_payment_intent' do
  puts ">> /capture_payment_intent called"

  begin
    id = params["payment_intent_id"]
    payment_intent = if params["amount_to_capture"]
      Stripe::PaymentIntent.capture(id, amount_to_capture: params["amount_to_capture"])
    else
      Stripe::PaymentIntent.capture(id)
    end

    log_info("✅ Captured PaymentIntent: #{id}")
    content_type :json
    status 200
    { intent: payment_intent.id, secret: payment_intent.client_secret }.to_json
  rescue Stripe::StripeError => e
    status 402
    log_info("❌ Capture failed: #{e.message}")
  end
end

# ✅ Cancel payment intent
post '/cancel_payment_intent' do
  puts ">> /cancel_payment_intent called"

  begin
    id = params["payment_intent_id"]
    payment_intent = Stripe::PaymentIntent.cancel(id)

    log_info("✅ Canceled PaymentIntent: #{id}")
    content_type :json
    status 200
    { intent: payment_intent.id, secret: payment_intent.client_secret }.to_json
  rescue Stripe::StripeError => e
    status 402
    log_info("❌ Cancel failed: #{e.message}")
  end
end
