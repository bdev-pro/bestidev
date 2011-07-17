class Admin::ProductUploadController < Admin::BaseController
  
  def index
    redirect_to :action => :new
  end
  
  def new
    @product_upload = ProductUpload.new
  end
  
  def create
    h , upload_results = ProductUpload.upload_data(params[:folder])
    flash[h] = upload_results
    render :new
  end
end
