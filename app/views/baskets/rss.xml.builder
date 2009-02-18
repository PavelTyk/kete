@title = t('baskets.rss.title', :site_name => SITE_NAME, :amount => @number_per_page.to_s)
xml.instruct! :xml, :version=>"1.0"
xml.rss(:version=>"2.0"){
  xml.channel{
    xml.title(@title)
    xml.link(request.protocol + request.host + request.request_uri)
    xml.description(t('baskets.rss.description'))
    xml.language('en-nz')
    for basket in @baskets
      xml.item do
        xml.title(basket.name)
        @basket_homepage = basket_index_url( :urlified_name => basket.urlified_name )
        xml.link(@basket_homepage)
        xml.guid(@basket_homepage)
      end
    end
  }
}
