require 'rack'
require 'rack/contrib'

require 'sinatra/base'
require 'sinatra/param'
require 'rack'

require 'sequel'

require 'venice'

module Rack
  class InAppPurchase < Sinatra::Base
    use Rack::PostBodyContentTypeParser
    helpers Sinatra::Param

    autoload :Product, 'rack/in-app-purchase/models/product'
    autoload :Receipt, 'rack/in-app-purchase/models/receipt'

    disable :raise_errors, :show_exceptions

    configure do
      Sequel.extension :core_extensions, :migration

      if ENV['DATABASE_URL']
        DB = Sequel.connect(ENV['DATABASE_URL'])
        Sequel::Migrator.run(DB, ::File.join(::File.dirname(__FILE__), "in-app-purchase/migrations"), table: 'in_app_purchase_schema_info')
      end
    end

    before do
      content_type :json
    end

    get '/products/identifiers' do
      Product.where(is_enabled: true).map(:product_identifier).to_json
    end

    post '/receipts/verify' do
      param :'receipt-data', String, required: true

      status 203

      begin
        receipt = Venice::Receipt.verify!(params[:'receipt-data'])
        latest = receipt.in_app.sort {|a,b| a.transaction_id.to_i <=> b.transaction_id.to_i }.last
        Receipt.create({ip_address: request.ip}.merge(latest.to_h))

        content = settings.content_callback.call(receipt) rescue nil

        {
          status: 0,
          receipt: latest.to_h,
          content: content
        }.select{|k,v| v}.to_json
      rescue Venice::Receipt::VerificationError => error
        {
          status: error.message
        }.to_json
      rescue
        halt 500
      end
    end
  end
end
