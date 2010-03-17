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

      def purchase(money, creditcard, options = {})
        response = authorize(money, creditcard, options)
        return response unless response.success?
        
        capture(money, response.authorization)
      end

      def authorize(money, creditcard, options = {})
        post = options_for_post(options)
        add_account(post, creditcard, options)
        add_payment_method(post, creditcard, options) if ok?(post[:account])
        if post[:validated]
          do_auth(money, post)
        else
          return error_from(post[:account])
        end
      end

      def capture(money, authorization, options = {})
        do_capture(money, authorization)
      end

    private
      def add_account(post, creditcard, options)
        post[:account], post[:created] = if options[:account_id].blank?
          Vindicia::Account.update({
            :merchantAccountId      => Time.now.to_i.to_s,
            :emailAddress           => options[:email],
            :warnBeforeAutobilling  => false,
            :name                   => [creditcard.first_name, creditcard.last_name].join(" ")
          })
        else
          Vindicia::Account.find(options[:account_id])
        end
      end

      def add_payment_method(post, creditcard, options)
        address = options[:billing_address] || options[:shipping_address] || options[:address]

        post[:account], post[:validated] = Vindicia::Account.updatePaymentMethod(post[:account].ref, {
          # Payment Method
          :type => 'CreditCard',
          :creditCard => {
            :account => creditcard.number,
            :expirationDate => expdate(creditcard),
            # creditcard.verification_value ??
          },
          :accountHolderName => [creditcard.first_name, creditcard.last_name].join(" "),
          :billingAddress => {
            :name => [creditcard.first_name, creditcard.last_name].join(" "),
            :addr1 => address[:address1].to_s,
            :city => address[:city].to_s,
            :district => address[:state].to_s,
            :country => address[:country].to_s,
            :postalCode => address[:zip].to_s
          },
          :merchantPaymentMethodId => options[:order_id]
        }, true, 'Validate')
        @failure = "Could not validate card" if post[:validated] == false
      end
      
      
      def do_auth(money, parameters)
        account = parameters[:account]
        payment_vid = account.paymentMethods.first.VID
        transaction = Vindicia::Transaction.auth({
          :account                => account.ref,
          :merchantTransactionId  => parameters[:order_id],
          :sourcePaymentMethod    => {:VID => payment_vid},
          :amount                 => money/100.0,
          #:currency               => money.currency,
          :transactionItems       => [{:sku => parameters[:sku], :name => parameters[:name], :price => money/100.0, :quantity => 1}]
        })
        response_for(transaction)
      end
      
      def do_capture(money, auth)
        transaction = Vindicia::Transaction.new(auth)
        ret, successful, failed, results = Vindicia::Transaction.capture([transaction.ref])
        transaction = Vindicia::Transaction.find(results[0].merchantTransactionId)
        @failure = "Capture failed" if successful.zero?
        response_for(transaction)
      end
      
      def response_for(transaction)
        response = transaction.values
        message = message_from(transaction.request_status)

        Response.new(success?(transaction.request_status), message, response, 
          :test => test_mode, 
          :authorization => response['merchantTransactionId']
        )
      end
      
      def message_from(request)
        msg = @failure if request.code == 200 or request.response =~ /\(Internal\)/
        msg ||= request.response
      end
      
      def error_from(soap_object)
        response = soap_object.values
        message = message_from(soap_object.request_status)
        test_mode = Vindicia.environment != :production
        Response.new(false, message, response, :test => test_mode)
      end
      
      def options_for_post(options)
        { :name => options[:name],
          :sku => options[:sku],
          :order_id => options[:order_id]
        }
      end
      
      def success?(request)
        @failure.nil? && request.code == 200
      end
      
    private
      def expdate(creditcard)
        "%4d%02d" % [creditcard.year, creditcard.month]
      end
      
      def ok?(response)
        response.request_status.code == 200
      end

      def test_mode
        Vindicia.environment != :production
      end

    end
  end
end

