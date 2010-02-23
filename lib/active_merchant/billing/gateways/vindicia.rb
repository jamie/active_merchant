module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    class VindiciaGateway < Gateway
      API_VERSION = "3.4"
      # Docs: http://www.vindicia.com/docs/soap/index.html?ver=3.4
      TEST_URL = "https://soap.prodtest.sj.vindicia.com/v#{API_VERSION}/soap.pl"
      LIVE_URL = "https://soap.vindicia.com/v#{API_VERSION}/soap.pl"

      # The countries the gateway supports merchants from as 2 digit ISO country codes
      self.supported_countries = ['CA', 'US'] # TODO: more?

      # The card types supported by the payment gateway
      # TODO: check?
      self.supported_cardtypes = [:visa, :master, :american_express, :discover]

      # The homepage URL of the gateway
      self.homepage_url = 'http://www.vindicia.com/'

      # The name of the gateway
      self.display_name = 'Vindicia'

      def initialize(options = {})
        begin
          require 'vindicia'
        rescue LoadError
          puts "The vindicia gem must be installed to use this gateway."
          raise
        end
        
        #requires!(options, :login, :password)
        @options = options
        Vindicia.authenticate(options[:login], options[:password])
        super
      end

      def authorize(money, creditcard, options = {})
        post = options_for_post(options)
        add_account(post, options)
        add_payment_method(post, creditcard, options)

        commit('authonly', money, post)
      end

      def purchase(money, creditcard, options = {})
        post = options_for_post(options)
        add_account(post, options)
        if !success?(post[:account].request_status)
          return error_from(post[:account])
        end
        add_payment_method(post, creditcard, options)

        commit('sale', money, post)
      end

      def capture(money, authorization, options = {})
        options[:auth] = authorization
        commit('capture', money, options)
      end

      private

      def add_account(post, options)
        if options[:account_id].blank?
          account, created = Vindicia::Account.update({
            :merchantAccountId      => Time.now.to_i.to_s,
            :emailAddress           => options[:email],
            :warnBeforeAutobilling  => false,
            :name                   => 'Integration User'
          })
          post[:account] = account
        else
          post[:account] = Vindicia::Account.find(options[:account_id])
        end
      end

      # does both creditcard and address
      def add_payment_method(post, creditcard, options)
        address = options[:billing_address] || options[:shipping_address] || options[:address]
        post[:account], validated = Vindicia::Account.updatePaymentMethod(post[:account].ref, {
          # Payment Method
          :type => 'CreditCard',
          :creditCard => {
            :account => creditcard.number,
            :expirationDate => expdate(creditcard),
            # creditcard.verification_value ??
          },
          :accountHolderName => 'John Smith',
          :billingAddress => {
            :name => [creditcard.first_name, creditcard.last_name].join(" "),
            :addr1 => address[:address1].to_s,
            :city => address[:city].to_s,
            :district => address[:state].to_s,
            :country => address[:country].to_s,
            :postalCode => address[:zip].to_s
          },
          :merchantPaymentMethodId => options[:order_id]
        })
      end
      
      def commit(action, money, parameters)
        # Parameters:
        # sku
        # name
        # transaction_id
        # account (as a Vindicia::Account)
        
        account = parameters[:account]
        
        case action
        when 'sale'
          payment_vid = account.paymentMethods.first['VID']
          cap_data = {
            :account                => account.ref,
            :merchantTransactionId  => parameters[:order_id],
            :sourcePaymentMethod    => {:VID => payment_vid},
            :amount                 => money/100.0,
            #:currency               => money.currency,
            :transactionItems       => [{:sku => parameters[:sku], :name => parameters[:name], :price => money/100.0, :quantity => 1}]
          }
          transaction = Vindicia::Transaction.authCapture(cap_data)
        when 'authonly'
          payment_vid = account.paymentMethods.first['VID']
          transaction = Vindicia::Transaction.auth({
            :account                => account.ref,
            :merchantTransactionId  => parameters[:order_id],
            :sourcePaymentMethod    => {:VID => payment_vid},
            :amount                 => money/100.0,
            #:currency               => money.currency,
            :transactionItems       => [{:sku => parameters[:sku], :name => parameters[:name], :price => money/100.0, :quantity => 1}]
          })
        when 'capture'
          # WIP
          transaction = Vindicia::Transaction.new(parameters[:auth])
          ret, successful, failed, results = Vindicia::Transaction.capture([transaction.ref])
          transaction = Vindicia::Transaction.find(results[0].merchantTransactionId)
        end

        response = transaction.values
        message = message_from(transaction.request_status)

        test_mode = Vindicia.environment != :production

        Response.new(success?(transaction.request_status), message, response, 
          :test => test_mode, 
          :authorization => response['merchantTransactionId']
        )
      end
      
      def message_from(request)
        request.response
      end
      
      def error_from(soap_object)
        response = soap_object.values
        message = message_from(soap_object.request_status)
        test_mode = Vindicia.environment != :production
        Response.new(false, message, response, :test => test_mode)
      end
      
      def options_for_post(options)
        { :name => options[:name],
          :sku => options[:sku]
        }
      end
      
      def success?(request)
        request.code == 200
      end
      
    private
      def expdate(creditcard)
        "%4d%02d" % [creditcard.year, creditcard.month]
      end

    end
  end
end

