# encoding: utf-8

require 'cgi'

# Доставка Walletone-Redexpress
#
# Рудимент. не используется
#
module W1
  class OrderDeliveryUpdateService
    def initialize(order)
      @order = order
    end

    def update_state
      W1.logger.debug message: 'OrderDeliveryService#update', order_id: order.id

      response
      W1.logger.info message: 'Response',
                     order_id: order.id,
                     response_body: response.body,
                     response_code: response.code

      raise "Неверный статус #{response.code}" unless response.code.to_i == 200

      state = case response_json['orderState']
              when 'delivery'
                order.commands.update_delivery_state_to_delivery!
              when 'done'
                order.commands.update_delivery_state_to_done!
              else
                W1.logger.error message: "Не распознанный статус #{response.body}", order_id: order.id
                raise Error, "Неизвестный orderState: #{response.body}"
              end

      W1.logger.info message: "Обновлен статус заказа #{state}", order_id: order.id

      # rescue => err
      # raise err if Rails.env.test?
      # W1.logger.error message: "Ошибка обновления статуса заказа #{err}", order_id: order.id
      # Bugsnag.notify err, metaData: { order_id: order.id }
    end

    private

    attr_reader :order

    def response
      # TODO: заменить на id заказа в W1
      @response ||= Net::HTTP.post_form uri, OrderId: order.id
    end

    def response_json
      @response_json ||= get_response_json
    end

    def get_response_json
      MultiJson.load response.body
    rescue MultiJson::ParseError
      {}
    end

    def uri
      @url ||= URI.parse W1::OpenApi::API_URL + 'order/state'
    end

    class Error < StandardError; end
  end
end
