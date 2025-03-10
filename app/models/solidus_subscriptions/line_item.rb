# The LineItem class is responsible for associating Line items to subscriptions.  # It tracks the following values:
#
# [Spree::LineItem] :spree_line_item The spree object which created this instance
#
# [SolidusSubscription::Subscription] :subscription The object responsible for
#   grouping all information needed to create new subscription orders together
#
# [Integer] :subscribable_id The id of the object to be added to new subscription
#   orders when they are placed
#
# [Integer] :quantity How many units of the subscribable should be included in
#   future orders
#
# [Integer] :interval How often subscription orders should be placed
#
# [Integer] :installments How many subscription orders should be placed
module SolidusSubscriptions
  class LineItem < ActiveRecord::Base
    include Interval

    belongs_to(
      :spree_line_item,
      class_name: 'Spree::LineItem',
      inverse_of: :subscription_line_items,
      optional: true,
    )
    has_one :order, through: :spree_line_item, class_name: 'Spree::Order'
    belongs_to(
      :subscription,
      class_name: 'SolidusSubscriptions::Subscription',
      inverse_of: :line_items,
      optional: true
    )

    validates :subscribable_id, presence: :true
    validates :quantity, numericality: { greater_than: 0 }
    validates :interval_length, numericality: { greater_than: 0 }, unless: -> { subscription }

    before_update :update_actionable_date_if_interval_changed
    after_update :update_spree_line_item_quanity, if: -> { saved_change_to_quantity? }
    after_destroy :update_spree_line_item_quanity

    delegate :name, :price, to: :product, prefix: true
    attr_accessor :admin_update

    def next_actionable_date
      dummy_subscription.next_actionable_date
    end

    def as_json(**options)
      options[:methods] ||= [:dummy_line_item, :next_actionable_date]
      super(options)
    end

    # Get a placeholder line item for calculating the values of future
    # subscription orders. It is frozen and cannot be saved
    def dummy_line_item
      li = LineItemBuilder.new([self]).spree_line_items.first
      return unless li

      li.order = dummy_order
      li.validate
      li.freeze
    end

    def interval
      subscription.try!(:interval) || super
    end

    def variant
      @variant ||= ::Spree::Variant.find(subscribable_id)
    end

    def product
      @product ||= variant.product
    end

    def variant_name
      result = [product.name]
      variant.ordered_option_values.each do |option_value|
        result << option_value.presentation
      end
      result.join(', ')
    end

    def quantity=(value)
      if persisted? && value.to_i.zero?
        destroy!
      else
        super
      end
    end

    private

    # Get a placeholder order for calculating the values of future
    # subscription orders. It is a frozen duplicate of the current order and
    # cannot be saved
    def dummy_order
      order = spree_line_item ? spree_line_item.order.dup : Spree::Order.create
      order.ship_address = subscription.shipping_address || subscription.user.ship_address if subscription

      order.freeze
    end

    # A place holder for calculating dynamic values needed to display in the cart
    # it is frozen and cannot be saved
    def dummy_subscription
      Subscription.new(line_items: [dup], interval_length: interval_length, interval_units: interval_units).freeze
    end

    def update_actionable_date_if_interval_changed
      if persisted? && subscription && (interval_length_changed? || interval_units_changed?)
        base_date = if subscription.installments.any?
          subscription.installments.last.created_at
        else
          subscription.created_at
        end

        new_date = interval.since(base_date)

        if new_date < Time.zone.now
          # if the chosen base time plus the new interval is in the past, set
          # the actionable_date to be now to avoid confusion and possible
          # mis-processing.
          new_date = Time.zone.now
        end

        subscription.actionable_date = new_date
      end
    end

    # * The spree_line_item quantity should be updated when the variant quantity changed
    #   in the cart of the original order. The admin_update is nil in this case.
    # * The spree_line_item quantity should be left unchanged in the original order
    #   when the variant quantity changed by admin on the subscription page in the Admin panel.
    #   The admin_update is True in this case.
    def update_spree_line_item_quanity
      return if admin_update || !spree_line_item

      spree_line_item.update(quantity: spree_line_item.subscription_line_items.reload.map(&:quantity).sum)
    end
  end
end
