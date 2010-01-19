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
        #requires!(options, :login, :password)
        @options = options
        super
      end

      def authorize(money, creditcard, options = {})
        post = {}
        add_invoice(post, options)
        add_creditcard(post, creditcard)
        add_address(post, creditcard, options)
        add_customer_data(post, options)

        commit('authonly', money, post)
      end

      def purchase(money, creditcard, options = {})
        post = {}
        add_invoice(post, options)
        add_creditcard(post, creditcard)
        add_address(post, creditcard, options)
        add_customer_data(post, options)

        commit('sale', money, post)
      end

      def capture(money, authorization, options = {})
        commit('capture', money, post)
      end

      private

      def add_customer_data(post, options)
      end

      def add_address(post, creditcard, options)
      end

      def add_invoice(post, options)
      end

      def add_creditcard(post, creditcard)
      end

      def parse(body)
      end

      def commit(action, money, parameters)
      end

      def message_from(response)
      end

      def post_data(action, parameters = {})
      end
    end
  end
end

