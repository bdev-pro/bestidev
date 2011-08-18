class AddOldPriceToProducts < ActiveRecord::Migration
  def self.up
    add_column :products, :old_price, :decimal
  end

  def self.down
    remove_column :products, :old_price
  end
end
