# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SolidusSubscriptions::UserDecorator, type: :model do
  describe 'destroy subscription user' do
    subject { subscription.user.update(deleted_at: Time.zone.now) }

    let(:end_date) { 6.months.from_now }
    let(:subscription) do
      create :subscription, :with_line_item, end_date: end_date, line_item_traits: [{ end_date: end_date }]
    end

    it "marks user's all active subscription canceled" do
      subject
      expect(subscription.reload.state).to eq 'canceled'
    end
  end
end
