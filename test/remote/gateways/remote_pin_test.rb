require 'test_helper'

class RemotePinTest < Test::Unit::TestCase
  def setup
    @gateway = PinGateway.new(fixtures(:pin))

    @amount = 100
    @credit_card = credit_card('5520000000000000')
    @declined_card = credit_card('4100000000000001')

    @options = {
      :email => 'roland@pin.net.au',
      :ip => '203.59.39.62',
      :order_id => '1',
      :billing_address => address,
      :description => "Store Purchase #{DateTime.now.to_i}"
    }
  end

  def test_successful_purchase
    assert response = @gateway.purchase(@amount, @credit_card, @options)
    assert_success response
  end

  def test_successful_purchase_without_description
    @options.delete(:description)
    assert response = @gateway.purchase(@amount, @credit_card, @options)
    assert_success response
  end

  def test_unsuccessful_purchase
    assert response = @gateway.purchase(@amount, @declined_card, @options)
    assert_failure response
  end

  # This is a bit manual as we have to create a working card token as
  # would be returned from Pin.js / the card tokens API which
  # falls outside of active merchant
  def test_store_and_charge_with_pinjs_card_token
    headers = {
      "Content-Type" => "application/json",
      "Authorization" => "Basic #{Base64.strict_encode64(@gateway.options[:api_key] + ':').strip}"
    }
    # Get a token equivalent to what is returned by Pin.js
    card_attrs = {
      :number => @credit_card.number,
      :expiry_month => @credit_card.month,
      :expiry_year => @credit_card.year,
      :cvc => @credit_card.verification_value,
      :name => "#{@credit_card.first_name} #{@credit_card.last_name}",
      :address_line1 => "42 Sevenoaks St",
      :address_city => "Lathlain",
      :address_postcode => "6454",
      :address_start => "WA",
      :address_country => "Australia"
    }
    url = @gateway.test_url + "/cards"

    body = JSON.parse(@gateway.ssl_post(url, card_attrs.to_json, headers))

    card_token = body["response"]["token"]

    store = @gateway.store(card_token, @options)
    assert_success store
    assert_not_nil store.authorization

    purchase = @gateway.purchase(@amount, card_token, @options)
    assert_success purchase
    assert_not_nil purchase.authorization
  end

  def test_store_and_customer_token_charge
    assert response = @gateway.store(@credit_card, @options)
    assert_success response
    assert_not_nil response.authorization

    token = response.authorization

    assert response1 = @gateway.purchase(@amount, token, @options)
    assert_success response1

    assert response2 = @gateway.purchase(@amount, token, @options)
    assert_success response2
    assert_not_equal response1.authorization, response2.authorization
  end

  def test_refund
    assert response = @gateway.purchase(@amount, @credit_card, @options)
    assert_success response
    assert_not_nil response.authorization

    token = response.authorization

    assert response = @gateway.refund(@amount, token, @options)
    assert_success response
    assert_not_nil response.authorization
  end

  def test_failed_refund
    assert response = @gateway.purchase(@amount, @credit_card, @options)
    assert_success response
    assert_not_nil response.authorization

    token = response.authorization

    assert response = @gateway.refund(@amount, token.reverse, @options)
    assert_failure response
  end

  def test_invalid_login
    gateway = PinGateway.new(:api_key => '')
    assert response = gateway.purchase(@amount, @credit_card, @options)
    assert_failure response
  end
end
