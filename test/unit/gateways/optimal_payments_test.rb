require File.dirname(__FILE__) + '/../../test_helper'

class OptimalPaymentTest < Test::Unit::TestCase
  def setup
    @gateway = OptimalPaymentGateway.new(
                 :login => 'login',
                 :password => 'password'
               )

    @credit_card = credit_card
    @amount = 100

    @options = {
      :order_id => '1',
      :billing_address => address,
      :description => 'Store Purchase'
    }
  end

  def test_successful_purchase
    @gateway.expects(:ssl_post).returns(successful_purchase_response)

    assert response = @gateway.purchase(@amount, @credit_card, @options)
    assert_instance_of Response, response
    assert_success response

    # Replace with authorization number from the successful response
    assert_equal '126740505', response.authorization
    assert response.test?
  end

  def test_unsuccessful_request
    @gateway.expects(:ssl_post).returns(failed_purchase_response)

    assert response = @gateway.purchase(@amount, @credit_card, @options)
    assert_failure response
    assert response.test?
  end

  private

  # Place raw successful response from gateway here
  def successful_purchase_response
    <<-XML
<ccTxnResponseV1 xmlns="http://www.optimalpayments.com/creditcard/xmlschema/v1">
  <confirmationNumber>126740505</confirmationNumber>
  <decision>ACCEPTED</decision>
  <code>0</code>
  <description>No Error</description>
  <authCode>112232</authCode>
  <avsResponse>B</avsResponse>
  <cvdResponse>M</cvdResponse>
  <detail>
    <tag>InternalResponseCode</tag>
    <value>0</value>
  </detail>
  <detail>
    <tag>SubErrorCode</tag>
    <value>0</value>
  </detail>
  <detail>
    <tag>InternalResponseDescription</tag>
    <value>no_error</value>
  </detail>
  <txnTime>2009-01-08T17:00:45.210-05:00</txnTime>
  <duplicateFound>false</duplicateFound>
</ccTxnResponseV1>
    XML
  end

  # Place raw failed response from gateway here
  def failed_purchase_response
    <<-XML
<ccTxnResponseV1 xmlns="http://www.optimalpayments.com/creditcard/xmlschema/v1">
  <confirmationNumber>126740506</confirmationNumber>
  <decision>DECLINED</decision>
  <code>3009</code>
  <actionCode>D</actionCode>
  <description>Your request has been declined by the issuing bank.</description>
  <avsResponse>B</avsResponse>
  <cvdResponse>M</cvdResponse>
  <detail>
    <tag>InternalResponseCode</tag>
    <value>160</value>
  </detail>
  <detail>
    <tag>SubErrorCode</tag>
    <value>1005</value>
  </detail>
  <detail>
    <tag>InternalResponseDescription</tag>
    <value>auth declined</value>
  </detail>
  <txnTime>2009-01-08T17:00:46.529-05:00</txnTime>
  <duplicateFound>false</duplicateFound>
</ccTxnResponseV1>
    XML
  end
end
