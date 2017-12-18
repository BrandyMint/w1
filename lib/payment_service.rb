module W1
  class PaymentService < BasePaymentService
    def perform_and_get_response
      # Явно принимаем некоторые тестовые заказы
      #
      if Settings.w1.allowed_orders.include? payment.payment_no
        return success_response
      end

      # Явно какой-то левый или тестовый платеж
      # https://bugsnag.com/brandymint/kiiiosk-dot-com/errors/557718e2ea1b57dee749cf65#request
      if payment.payment_no.blank?
        W1.info message: 'Платеж принят автоматически без присоединения к существующему заказу',
                payment: payment.to_s,
                vendor_id: vendor.id
        return success_response
      end

      # TODO Убрать
      if payment.payment_no =~ /merchant-/ || payment.payment_no =~ /kiosk-734/
        W1.info message: 'Тестовый рекурентный платеж принят автоматически без присоединения к существующему заказу',
                payment: payment.to_s,
                vendor_id: vendor.id
        return success_response
      end

      raise NoSignature if payment.signature.blank?
      raise OrderNotFound, "#{payment.payment_no} order not found" if payment.order.blank?
      raise InvalidPayment unless payment.valid?

      if payment.accepted?
        return success_payment
      else
        return failed_payment
      end
    rescue => err
      error_catched err
    end

    private

    def error_catched(err)
      W1.error message: 'Ошибка проведения платежа',
               error: err.to_s,
               vendor_id: vendor.id,
               payment: payment.to_s

      Bugsnag.notify err, metaData: { payment: payment, vendor_id: vendor.id }

      retry_response("Внутренняя ошибка #{err}")
    end

    def success_payment
      W1.info message: "[order_id=#{payment.order}] Получен платеж заказа.",
              vendor_id: vendor.id,
              payment:   payment.to_s
      begin
        payment.order.order_payment.pay! payment
      rescue Workflow::NoTransitionAllowed => err
        Rails.logger.error err
        Bugsnag.notify err
        OrderNotificationService.new(payment.order).canceled_order_paid
      end
      success_response
    end

    def failed_payment
      W1.error message: "[order_id=#{payment.order}] Платеж не принят",
               vendor_id: vendor.id,
               payment:   payment.to_s

      payment.order.order_payment.fail! payment if payment.order.present?

      retry_response('Платеж не валидный или не полный')
    end

    def success_response
      'WMI_RESULT=OK'
    end

    def retry_response(message)
      "WMI_RESULT=RETRY&WMI_DESCRIPTION=#{CGI.escape(message)}"
    end

    def payment
      @payment ||= W1::PaymentService::Notify.new params, vendor
    end
  end
end
