require 'test_helper'
require 'pp'

class RemoteVindiciaTest < Test::Unit::TestCase
  def setup
    @gateway = VindiciaGateway.new(fixtures(:vindicia))

    @amount = 4900
    @credit_card = credit_card('4485983356242217')
    @declined_card = credit_card('4485983356242216')

    @options = {
      :name => "Premium Subscription",
      :sku => "PREMIUM_USD",
      :order_id => Time.now.to_i,
      :billing_address => address,
      :description => 'Store Purchase'
    }
  end

  def test_successful_purchase
    assert response = @gateway.purchase(@amount, @credit_card, @options)
    assert_success response
    assert_equal 'OK', response.message
  end

  def test_unsuccessful_purchase
    assert response = @gateway.purchase(@amount, @declined_card, @options)
    assert_failure response
    assert_equal 'Could not validate card', response.message
  end
  
  def test_authorize
    assert auth = @gateway.authorize(@amount, @credit_card, @options)
    assert_success auth
    assert_equal 'OK', auth.message
    assert auth.authorization
  end

  def test_capture
    assert response = @gateway.authorize(@amount, @credit_card, @options)
    assert capture = @gateway.capture(@amount, response.authorization)
    assert_success capture
  end

  def test_failed_capture
    assert response = @gateway.capture(@amount, '')
    assert_failure response
    assert_match 'Capture failed', response.message
  end

  def test_invalid_login
    gateway = VindiciaGateway.new(
                :login => '',
                :password => ''
              )
    assert response = gateway.purchase(@amount, @credit_card, @options)
    assert_failure response
    assert_equal 'Permission denied to domain "soap"', response.message
  end
end
