require 'test_helper'

class RemoteVindiciaTest < Test::Unit::TestCase
  def setup
    @gateway = VindiciaGateway.new(fixtures(:vindicia))

    @sku = 'em-2-PREMIUM-USD'
    @credit_card = credit_card('4485983356242217')
    @declined_card = credit_card('4555555555555550')

    @options = {
      :order_id => '1',
      :billing_address => address,
      :description => 'Store Purchase'
    }
  end

  # def test_successful_purchase
  #   assert response = @gateway.purchase(@sku, @credit_card, @options)
  #   assert_success response
  #   assert_equal 'OK', response.message
  # end
  # 
  # def test_unsuccessful_purchase
  #   assert response = @gateway.purchase(@sku, @declined_card, @options)
  #   assert_failure response
  #   assert_equal 'Unable to create autobill:  Payment method validation failed.', response.message
  # end

  def test_successful_subscribe
    assert response = @gateway.purchase(@sku, @credit_card, @options)
    assert_success response
    assert_equal 'OK', response.message
  end

  def test_unsuccessful_subscribe
    assert response = @gateway.purchase(@sku, @declined_card, @options)
    assert_failure response
    assert_equal 'Unable to create autobill:  Payment method validation failed.', response.message
  end

  def xtest_authorize_and_capture
    assert auth = @gateway.authorize(@sku, @credit_card, @options)
    assert_success auth
    assert_equal 'Success', auth.message
    assert auth.authorization
    assert capture = @gateway.capture(@sku, auth.authorization)
    assert_success capture
  end

  def test_failed_capture
    assert response = @gateway.capture(@sku, '')
    assert_failure response
    assert_match /Unable to save AutoBill/, response.message
  end

  def test_invalid_login
    gateway = VindiciaGateway.new(
                :login => '',
                :password => ''
              )
    assert response = gateway.purchase(@sku, @credit_card, @options)
    assert_failure response
    assert_equal 'Permission denied to domain "soap"', response.message
  end
end
