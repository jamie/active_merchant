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

        #requires!(options, :login, :password, :env)
        @options = options
        Vindicia.authenticate(options[:login], options[:password], options[:env]||:prodtest)
        super
      end

      def configure_risk(options)
        @risk_fail = options[:risk_fail] || 100
        @risk_moderate = options[:risk_moderate] || 100

        @cvn_fail = options[:cvn_fail] || ['N', 'P', 'S']
        @cvn_moderate = options[:cvn_moderate] || ['U', '']
        #@cvv_approve = ['M']

        @avs_fail = options[:avs_fail] || ['N', 'C', 'E']
        @avs_moderate = options[:avs_moderate] || ['A', 'B', 'W', 'Z', 'P', 'U', 'I']
        #@avs_approve = %w(X Y D M S G)
      end

      def purchase(money, creditcard, options = {})
        response = authorize(money, creditcard, options)
        return response if response.fraud_review? or !response.success?

        capture(money, response.authorization)
      end

      def authorize(money, creditcard, options = {})
        extract_address!(options, creditcard)
        post = auth_post(creditcard, options)

        do_auth(money, post, options)
      end

      def capture(money, authorization, options = {})
        do_capture(money, authorization)
      end

      def stored_purchase(money, authorization, options = {})
        # authorization should be the order_id passed in for the previous
        # transaction.
        response = stored_authorize(money, authorization, options)
        return response if response.fraud_review? or !response.success?

        capture(money, response.authorization)
      end

      def stored_authorize(money, authorization, options = {})
        # authorization should be the order_id passed in for the previous
        # transaction.
        extract_address!(options)
        post = stored_auth_post(authorization, options)

        do_auth(money, post, options)
      end


    private
      def name_on(creditcard)
        [creditcard.first_name, creditcard.last_name].join(" ")
      end

      def extract_address!(options, creditcard=nil)
        address = options[:billing_address] || options[:shipping_address] || options[:address]
        return if address.nil?
        options[:address_hash] = {
          :addr1      => address[:address1].to_s,
          :city       => address[:city].to_s,
          :district   => address[:state].to_s,
          :country    => address[:country].to_s,
          :postalCode => address[:zip].to_s
        }
        options[:address_hash][:name] = name_on(creditcard) if creditcard
      end

      def auth_post(creditcard, options)
        {
          :account => {
            # TODO: should be passed in, em-id
            :merchantAccountId      => options[:account_id],
            :emailAddress           => options[:email],
            :warnBeforeAutobilling  => false,
            :name                   => name_on(creditcard)
          },

          :sourcePaymentMethod => {
            # Payment Method
            :type => 'CreditCard',
            :creditCard => {
              :account        => creditcard.number,
              :expirationDate => expdate(creditcard),
            },
            :accountHolderName => name_on(creditcard),
            :billingAddress => options[:address_hash],
            :nameValues => [{:name => 'CVN', :value => creditcard.verification_value}],
            :merchantPaymentMethodId => options[:order_id]
          }
        }
      end

      def stored_auth_post(authorization, options)
        {
          :account => {:merchantAccountId => options[:account_id]},
          :sourcePaymentMethod => {:merchantPaymentMethodId => authorization}
        }
      end

      def do_auth(money, post, options)
        configure_risk(options)

        post[:nameValues] = options[:name_values] if options[:name_values]
        transaction = Vindicia::Transaction.auth(post.merge({
          :merchantTransactionId  => options[:order_id],
          :amount                 => money/100.0,
          :currency               => options[:currency] || 'USD',
          :shippingAddress        => options[:address_hash],
          :sourceIp               => options[:ip] || "",
          :transactionItems       => [{:sku => options[:sku], :name => options[:name], :price => money/100.0, :quantity => 1, :taxClassification => (options[:tax_classification] || "Service")}]
        }), @risk_fail, false)

        if transaction.request_status.returnCode == "200"
          if auth_log = transaction.statusLog.detect{|log|log.status == 'Authorized'}
            avs_code = auth_log.creditCardStatus.avsCode
            cvn_code = auth_log.creditCardStatus.cvnCode
          else
            # no Auth log entry, so fail normally
            avs_code = cvn_code = []
          end

          if @cvn_fail.include? cvn_code
            @failure = "CVN check failed"
            Vindicia::Transaction.cancel([transaction.ref])
            response_for(transaction)
          elsif @avs_fail.include? avs_code
            @failure = "AVS check failed"
            Vindicia::Transaction.cancel([transaction.ref])
            response_for(transaction)
          elsif @cvn_moderate.include? cvn_code or @avs_moderate.include? avs_code
            @failure = "AVS/CVN triggered fraud review"
            response_for(transaction, true)
          else
            response_for(transaction)
          end
        else
          response = transaction.to_hash
          message = message_from(transaction.request_status)
          Response.new(false, message, response,
            :test => test_mode,
            :fraud_review => false,
            :authorization => ""
          )
        end
      end

      def do_capture(money, auth)
        transaction = Vindicia::Transaction.new(auth)
        ret, successful, failed, results = Vindicia::Transaction.capture([transaction.ref])
        # TODO: don't do this next line, check 'results' for info
        transaction = Vindicia::Transaction.find(results[0].merchantTransactionId)
        @failure = "Capture failed" if successful.zero?
        response_for(transaction)
      end

      def response_for(transaction, review=false)
        response = transaction.to_hash
        message = message_from(transaction.request_status)

        Response.new(success?(transaction.request_status), message, response,
          :test => test_mode,
          :fraud_review => review,
          :authorization => response['merchantTransactionId']
        )
      end

      def message_from(request)
        msg = @failure if request.code == 200 or request.response =~ /\(Internal\)/
        msg ||= request.response
      end

      def error_from(soap_object)
        response = soap_object.to_hash
        message = message_from(soap_object.request_status)
        test_mode = Vindicia.environment != :production
        Response.new(false, message, response, :test => test_mode)
      end

      def success?(request)
        @failure.nil? && request.code == 200
      end


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
