require 'test_helper'

class RemoteVindiciaTest < Test::Unit::TestCase
  def setup
    @gateway = VindiciaGateway.new(fixtures(:vindicia))

    @amount = 4900
    @credit_card = credit_card('4485983356242217')
    @declined_card = credit_card('4555555555555550')

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

  def xtest_unsuccessful_purchase
    @options[:sku] = ""
    # TODO: remove above line and figure out cc # that will fail properly
    assert response = @gateway.purchase(@amount, @declined_card, @options)
    assert_failure response
    assert_equal 'Unable to create autobill:  Payment method validation failed.', response.message
  end

  def test_authorize_and_capture
    assert auth = @gateway.authorize(@amount, @credit_card, @options)
    assert_success auth
    assert_equal 'OK', auth.message
    assert auth.authorization
    assert capture = @gateway.capture(@amount, auth.authorization)
    assert_success capture
  end

  def xtest_failed_capture
    assert response = @gateway.capture(@amount, '')
    assert_failure response
    assert_match /Unable to save AutoBill/, response.message
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
