class ExportatorHooks < Spree::ThemeSupport::HookListener
  # custom hooks go here
  insert_after :admin_tabs do
   %(<%= tab(:product_export_index) %>)
  end
  insert_after :admin_tabs do
   %(<%= tab(:product_upload_index) %>)
  end
end
