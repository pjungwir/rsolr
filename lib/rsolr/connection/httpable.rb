# A module that defines the interface and top-level logic for http based connection classes.
# Httpable provides URL parsing and handles proxy logic.

module RSolr::Connection::Httpable
  
  attr_reader :opts, :uri, :proxy
  
  # opts can have:
  #   :url => 'http://localhost:8080/solr/'
  # TODO: Implement a ping here and throw an error if it fails?
  def initialize opts={}
    opts[:url] ||= 'http://127.0.0.1:8983/solr/'
    @opts = opts
    @uri = new_uri opts[:url]
    @proxy = new_uri opts[:proxy] if opts[:proxy]
  end
  
  # send a request to the connection
  # request 'select', :q=>'*:*'
  #
  # request 'update', {:wt=>:xml}, '</commit>'
  # 
  # force a post where the post body is the param query
  # request 'update', "<optimize/>", {:debugQuery => true}, {:method=>:post}
  #
  def request path, params={}, *extra
    extra = extra.dup
    opts = extra[-1].kind_of?(Hash) ? extra.pop : {}
    data = extra[0]
    send_and_receive path, params, data, opts
  end
  
  # Sends the request, returns a context hash with :request and :response keys
  # or raises and error.
  # If an error is raised, a "context" is attached
  # which exposes the original request info:
  #   $!.context[:request][:uri]
  # * RSolr::RequestError is raised if the response code is NOT 200
  def send_and_receive path, params, data, opts
    context = {:request => create_request_context(path, params, data, opts)}
    begin
      context[:response] = execute_request context[:request]
    rescue
      e = $!
      e.extend RSolr::Contextable
      e.context = context
      raise e
    end
    raise RSolr::RequestError.new(context) unless context[:response][:status_code].to_i == 200
    context
  end
  
  # Creates a Hash based "context"
  # which contains all of the information sent to Solr
  # The keys are:
  #   :uri, :data, :headers
  def create_request_context path, params, data = nil, opts={}
    new_uri = @uri.merge_with_params(path, params)
    context = {:uri => new_uri, :data => data}
    if opts[:method] == :post
      raise "Don't send POST data when using :method => :post" unless data.to_s.empty?
      # force a POST, use the query string as the POST body
      context.merge! :data => new_uri.query, :headers => {'Content-Type' => 'application/x-www-form-urlencoded'}
    elsif data
      context.merge! :headers => {'Content-Type' => 'text/xml; charset=utf-8'}
    end
    context
  end
  
  protected
  
  # Inspects the context hash and executes the request.
  # If data is being sent OR if :method => :post, this is a POST.
  # Merges the :response into the "context".
  def execute_request request_context
    status_code, headers, body = request_context[:data] ? 
      post(request_context[:uri], request_context[:data], request_context[:headers]) : 
      get(request_context[:uri])
    {:status_code => status_code, :headers => headers, :body => body}
  end
  
  # Creates a new (rsolr::uri modified) URI object.
  # "url" is a url string.
  # If the url doesn't end with a slash, one is appended.
  def new_uri url
    url << '/' unless url[-1] == ?/
    URI.parse(url).extend RSolr::Uri
  end
  
end