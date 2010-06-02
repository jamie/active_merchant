require 'test_helper'
require 'pp'

class RemoteVindiciaTest < Test::Unit::TestCase
  def setup
    @gateway = VindiciaGateway.new(fixtures(:vindicia))

    @amount = 4900
    @credit_card = credit_card('4485983356242217')
    @broken_card = credit_card('4485983356242216')

    unique_me = (Time.now.to_i + Time.now.usec).to_s
    order_id = unique_me
    @options = {
      :name => "Premium Subscription",
      :email => "test@example.com",
      :sku => "PREMIUM_USD",
      :order_id => "order_#{unique_me}",
      :account_id => "test_account_#{unique_me}",
      :currency => 'USD',
      :billing_address => address,
      :description => 'Online Purchase',
    }
    @stored_options = {
      :name => "Premium Subscription",
      :sku => "PREMIUM_USD-RE",
      :order_id => "order_#{unique_me}s",
      :account_id => "test_account_#{unique_me}",
      :currency => 'USD',
      :billing_address => address,
      :description => 'Online Purchase',
    }
  end

  def test_successful_purchase
    assert response = @gateway.purchase(@amount, @credit_card, @options)
    assert_success response
    assert_equal 'OK', response.message
  end

  def test_unsuccessful_purchase
    assert response = @gateway.purchase(@amount, @broken_card, @options)
    assert_failure response
    assert_match /Failed to create Payment/, response.message
  end

  def test_purchase_needing_moderation
    assert response = @gateway.purchase(@amount, credit_card('5135299256640694'), @options)
    assert_failure response
    assert response.fraud_review?
    assert_equal 'AVS/CVN triggered fraud review', response.message
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

  def test_capture_after_fraud_review
    assert response = @gateway.purchase(@amount, credit_card('5135299256640694'), @options)
    assert_failure response
    assert response.fraud_review?
    assert_equal 'AVS/CVN triggered fraud review', response.message

    # Don't use the same gateway instance for multiple requests, it bleeds error messages
    @gateway = VindiciaGateway.new(fixtures(:vindicia))
    assert capture = @gateway.capture(@amount, response.authorization)
    assert_success capture
  end

  def test_failed_capture
    assert response = @gateway.capture(@amount, '')
    assert_failure response
    assert_match 'Capture failed', response.message
  end

  def test_stored_data_purchase
    assert response = @gateway.purchase(@amount, @credit_card, @options)
    assert_success response
    assert_equal 'OK', response.message
    assert response.authorization

    # Don't use the same gateway instance for multiple requests, it bleeds error messages
    @gateway = VindiciaGateway.new(fixtures(:vindicia))
    assert stored_purchase = @gateway.stored_purchase(@amount, @options[:order_id], @stored_options)
    assert_success stored_purchase
  end

  def test_stored_data_authorize_and_capture
    assert response = @gateway.purchase(@amount, @credit_card, @options)
    assert_success response
    assert_equal 'OK', response.message
    assert response.authorization

    # Don't use the same gateway instance for multiple requests, it bleeds error messages
    # Also, using @amount*2 and diff options hash so Vindicia doesn't think it's a dupe
    @gateway = VindiciaGateway.new(fixtures(:vindicia))
    assert auth = @gateway.stored_authorize(@amount, @options[:order_id], @stored_options)
    assert_success auth
    assert_equal 'OK', auth.message
    assert auth.authorization

    # Don't use the same gateway instance for multiple requests, it bleeds error messages
    @gateway = VindiciaGateway.new(fixtures(:vindicia))
    assert capture = @gateway.capture(@amount*2, auth.authorization)
    assert_success capture
  end

  def test_invalid_login
    gateway = VindiciaGateway.new(:login => '', :password => '')
    assert response = gateway.purchase(@amount, @credit_card, @options)
    assert_failure response
    assert_equal 'Permission denied to domain "soap"', response.message
  end
end
