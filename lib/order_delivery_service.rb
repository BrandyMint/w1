# Информируем W1 что надо начать доставку
#
require 'cgi'
require 'open-uri'

module W1
  # Redexpress
  class OrderDeliveryService
    def initialize(order, checkout_url: W1::API_CHECKOUT_URL)
      raise 'No order in arguments' unless order.is_a? Order
      @order = order
      @checkout_url = checkout_url
    end

    def create
      log_start

      response = make_response

      redirect_uri = pull_redirect_uri response.body

      log_external_id redirect_uri
      make_redirect redirect_uri

      order.order_delivery.update_attributes! agent_notify_state: 'done'
    rescue => err
      perform_rescue err
    end

    private

    delegate :order_delivery, to: :order

    attr_reader :order, :checkout_url

    def log_start
      order_delivery.update_attributes!(
        agent_notify_at:     Time.zone.now,
        agent_notify_fields: fields.to_s,
        agent_notify_state:  'start'
      )

      debug message: 'OrderDeliveryService#create', fields: fields.to_s
    end

    def log_external_id(redirect_uri)
      external_id = pull_w1_order_id redirect_uri

      order.order_payment.update_attributes! external_id: external_id
      order.order_delivery.update_attributes!(
        external_id:           external_id,
        agent_notify_state:    'redirect',
        agent_notify_redirect: redirect_uri.to_s
      )
      debug message: "Устанавливаем external_id для delivery #{order_id}",
            url:         redirect_uri.to_s,
            external_id: external_id
    end

    def order_id
      order.id
    end

    def perform_rescue(err)
      order_delivery.update_attribute :agent_notify_state, :error
      error message: 'Delivery order', error: err.inspect
      Bugsnag.notify err, metaData: { order_id: order.id, fields: fields }
      raise err
    end

    #  <html><head><title>Object moved</title></head><body>
    #  <h2>Object moved to <a href="https://www.walletone.com/checkout/Default.aspx?i=347632112961&amp;m=127696943127">here</a>.</h2>;
    #  </body></html>

    def pull_redirect_uri(body)
      Addressable::URI.parse Nokogiri::HTML(body).css('body/h2/a').attr('href').value
    rescue => err
      Bugsnag.notify err, metaData: { body: body, order_id: order.id }
      nil
    end

    def make_redirect(redirect_uri)
      raise "Must be a Addressable::URI #{redirect_uri}" unless redirect_uri.is_a?(Addressable::URI)

      debug message:  "Делаю подтверждающий редирект по заказу #{order_id}",
            url:      redirect_uri.to_s,
            order_id: order_id

      redirect_uri = add_host_if_need redirect_uri

      # Идем со всеми редиректами
      res = open(redirect_uri.to_s).read

      debug message:       'Подтверждающий редирект - DONE',
            order_id:      order_id,
            url:           redirect_uri.to_s,
            response_body: res
    rescue => err
      error message:       "Ошибка подтверждающего редиректа: #{err}",
            order_id:      order_id,
            url:           redirect_uri.to_s,
            response_body: res
      Bugsnag.notify err, metaData: { redirect_uri: redirect_uri, order_id: order.id }
      raise err
    end

    def error(params)
      W1.logger.error params.merge order_id: order.id
    end

    def info(params)
      W1.logger.info params.merge order_id: order.id
    end

    def debug(params)
      W1.logger.debug params.merge order_id: order.id
    end

    def make_response
      res = Net::HTTP.post_form uri, fields

      save_response res

      info message:       'Delivery order',
           url:           uri.to_s,
           response_code: res.code,
           response_body: res.body,
           fields:        fields.to_s

      unless res.code.to_i == 302
        Bugsnag.notify StandardError,
          metaData: { uri: uri.to_s, order_id: order.id, body: res.body, code: res.code, fields: fields }
        save_response res
        raise W1::OrderDeliveryService::Error.new res
      end

      res
    end

    def save_response(res)
      name = ['redexpess-w1', order.vendor_id, order.id, Time.zone.now.to_i, res.code].join('-') + '.html'
      file = Rails.root.join 'log', name
      File.open(file, 'wb') { |f| f.write res.body }
      order_delivery.update_attributes agent_notify_dump: res.body
    rescue => err
      Bugsnag.notify err, metaData: { order_id: order.id }
    end

    def pull_w1_order_id(uri)
      raise "Must be a Addressable::URI #{uri}" unless uri.is_a?(Addressable::URI)
      # "https://www.walletone.com/checkout/Default.aspx?i=347632097524&m=127696943127"
      val = uri.query_values['i']
      raise "No order id in uri: #{uri} for order_id #{order_id}" if val.blank?

      val
    end

    def uri
      @url ||= URI.parse checkout_url
    end

    def fields
      @fields ||= FormOptions.generate order, true
    end

    # /checkout/State.aspx?m=105981838491&i=344425426393&pt=AssistRUB-CreditCardRUB
    # https://www.walletone.com/checkout/Default.aspx?i=347632066531&m=127696943127
    def add_host_if_need(uri)
      raise "Must be a Addressable::URI #{uri}" unless uri.is_a?(Addressable::URI)

      return uri if uri.host.present?
      uri = uri.dup

      aa = Addressable::URI.parse checkout_url
      uri.host   = aa.host
      uri.scheme = aa.scheme

      uri.to_s
    end
  end
end

class W1::OrderDeliveryService::Error < StandardError
  def initialize(response)
    @response = response
  end

  def message
    "Ошибка отправки запроса: #{@response.code.to_i}"
  end

  def inspect
    "#{@response.code} #{@response.body}"
  end
end
