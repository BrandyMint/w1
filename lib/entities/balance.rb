class W1::Entities::Balance
  include Virtus.model

  # {"CurrencyId"=>643,
  # "Amount"=>0.0,
  # "OverLimitAmount"=>0.0,
  # "SafeAmount"=>0.0,
  # "HoldAmount"=>0.0,
  # "Overdraft"=>0.0,
  # "AvailableAmount"=>0.0,
  # "IsNative"=>true,
  # "VisibilityType"=>"Always",
  # "IsAccountIdentified"=>false,
  # "IdentificationLevel"=>0},

  attribute :CurrencyId, Integer, required: true
  attribute :Amount, Float, required: true
  attribute :SafeAmount, Float
  attribute :HoldAmount, Float
  attribute :Overdraft, Float
  attribute :AvailableAmount, Float

  attribute :IsNative, Boolean
  attribute :VisibilityType, String
  attribute :IsAccountIdentified, Boolean
  attribute :IdentificationLevel, Integer

  def to_s; end

  def amount
    @amount ||= Money.new self.Amount * currency.subunit_to_unit, currency
  end

  def currency
    @currency ||= Money::Currency.find_by_iso_numeric(self.CurrencyId)
  end
end
