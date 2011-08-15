class PagesController < Spree::BaseController

  layout 'besti_static'
  before_filter :fetch_locale, :only =>[:who_we_are, :bdev]

  def contact
  end

  def legal_advice
  end
  
  def conditions
  end

  def who_we_are
  end

  def our_athletes
  end

  def fake_home
  end

  def bdev
  end

  private
    def fetch_locale
      @current_locale =  session[:locale] || Spree::Config[:default_locale]
    end

end
