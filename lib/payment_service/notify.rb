# Пример данных
# https://www.honeybadger.io/projects/39607/faults/9648411#notice-summary
# https://www.honeybadger.io/projects/39607/faults/10120189#notice-summary
module W1
  class PaymentService::Notify
    attr_accessor :params, :vendor

    ORDER_ACCEPTED = 'Accepted'.freeze

    def initialize(params, vendor)
      @params = params
      @vendor = vendor
    end

    def valid?
      signature.present? && signature == calculated_signature
    end

    def accepted?
      state.present? && state == ORDER_ACCEPTED
    end

    def order
      @order ||= vendor.orders.find_by_external_id(payment_no)
    end

    def inspect
      params.to_hash
    end

    def payment_no
      params[WMI_PAYMENT_NO]
    end

    def signature
      params[WMI_SIGNATURE]
    end

    delegate :to_s, to: :inspect

    private

    def state
      params[WMI_ORDER_STATE]
    end

    def calculated_signature
      W1.generate_signature_from_options params, vendor.vendor_walletone.merchant_sign_key
    end
  end
end
