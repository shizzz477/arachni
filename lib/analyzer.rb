=begin
  $Id$

                  Arachni
  Copyright (c) 2010 Anastasios Laskos <tasos.laskos@gmail.com>

  This is free software; you can copy and distribute and modify
  this program under the term of the GPL v2.0 License
  (See LINCENSE file for details)

=end

module Arachni

#
# Analyzer class<br/>
# Analyzes HTML code extracting forms, links and cookies
# depending on user opts.
#
# @author: Zapotek <zapotek@segfault.gr> <br/>
# @version: 0.1-planning
#
class Analyzer

    include Arachni::UI::Output

    #
    # Structure of the html elements in Hash format
    # @return [Hash<String, Hash<Array, Hash>>]
    #
    attr_reader :structure

    #
    # Array of extracted HTML forms
    # @return [Array<Hash <String, String> >]
    #
    attr_reader :forms

    #
    # Array of extracted HTML links
    # @return [Array<Hash <String, String> >]
    #
    attr_reader :links

    #
    # Array of extracted cookies
    # @return [Array<Hash <String, String> >]
    #
    attr_reader :cookies

    #
    # Hash of options passed to initialize( opts ).
    #
    attr_reader :opts

    #
    # Constructor <br/>
    # Instantiates Analyzer class with user options.
    #
    # @param  [{String => Symbol}] opts  hash with option => value pairs
    #
    def initialize( opts )
        @url = ''
        @opts = opts
        @structure = Hash.new
    end

    #
    # Runs the Analyzer and extracts forms, links and cookies
    #
    # @param [String] url the url of the HTML code, mainly used for debugging
    # @param [String] html HTML code  to be analyzed
    # @param [Hash] headers HTTP headers
    #
    # @return [Hash<String, Hash<Array, Hash>>] HTML elements
    #
    def run( url, html, headers )

        @url = url

        msg = "["

        elem_count = 0
        if @opts[:audit_forms]
            @structure['forms'] = @forms = get_forms( html )
            elem_count += form_count = @structure['forms'].length
            msg += "Forms: #{form_count}\t"
        end

        if @opts[:audit_links]
            @structure['links'] = @links = get_links( html )
            elem_count += link_count = @structure['links'].length
            msg += "Links: #{link_count}\t"
        end

        if @opts[:audit_cookies]
            @structure['cookies'] = @cookies =
                get_cookies( headers['set-cookie'].to_s )
            
            elem_count += cookie_count =  @structure['cookies'].length
            msg += "Cookies: #{cookie_count}"
        end

        msg += "]\n\n"
        print_verbose( msg )

        return @structure
    end

    # TODO: Add support for radio buttons.
    #
    # Extracts forms from HTML document
    #
    # @param  [String] html
    #
    # @return [Array<Hash <String, String> >] array of forms
    #
    def get_forms( html )

        elements = []

        begin
            forms = html.scan( /<form(.*?)<\/form>/ixm )
        rescue Exception => e
            print_error( "Error: Couldn't get forms from '" + @url +
            "' [" + e.to_s + "]" )
            return {}
        end

        forms.each_with_index {
            |form, i|
            form = form[0]

            elements[i] = Hash.new
            elements[i]['textarea'] = get_form_textareas( form )
            elements[i]['select']   = get_form_selects( form )
            elements[i]['input']    = get_form_inputs( form )

            # merge the form elements to make auditing easier
            elements[i]['auditable'] = 
                elements[i]['input'] | elements[i]['textarea']
            
            elements[i]['auditable'] =
                merge_select_with_input( elements[i]['auditable'],
                    elements[i]['select'] )

            elements[i]['attrs']    = get_form_attrs( form )
        }

        elements
    end

    def merge_select_with_input( inputs, selects )

        new_arr = []
        inputs.each {
            |input|
            new_arr << input
        }

        i = new_arr.size
        selects.each {
            |select|
            new_arr << select['attrs']
        }

        new_arr
    end

    #
    # Extracts links from HTML document
    #
    # @param  [String] html
    #
    # @return [Array<Hash <String, String> >] of links
    #
    def get_links( html )
        links = []
        get_elements_by_name( 'a', html ).each_with_index {
            |link, i|

            link['href'] = to_absolute( link['href'] )

            if !link['href'] then next end

            links[i] = link
            links[i]['vars'] = get_link_vars( link['href'] )
        }
    end

    #
    # Extracts cookies from an HTTP headers
    #
    # @param  [String] headers HTTP headers
    #
    # @return [Array<Hash <String, String> >] of cookies
    #
    def get_cookies( headers )
        cookies = WEBrick::Cookie.parse_set_cookies( headers )

        cookies_arr = []

        cookies.each_with_index {
            |cookie, i|
            cookies_arr[i] = Hash.new

            cookie.instance_variables.each {
                |var|
                value = cookie.instance_variable_get( var ).to_s
                value.strip!
                cookies_arr[i][var.to_s.gsub( /@/, '' )] =
                value.gsub( /[\"\\\[\]]/, '' )
            }
        }

        return cookies_arr
    end

    def get_link_vars( link )
        if !link then return {} end

        var_string = link.split( /\?/ )[1]
        if !var_string then return {} end

        var_hash = Hash.new
        var_string.split( /&/ ).each {
            |pair|
            name, value = pair.split( /=/ )
            var_hash[name] = value
        }

        var_hash

    end

    private

    #
    # Parses the attributes inside the <form ....> tag
    #
    # @param  [String] form   HTML code for the form tag
    #
    # @return [Array<Hash<String, String>>]
    #
    def get_form_attrs( form )
        form_attr_html = form.scan( /(.*?)>/ixm )
        get_attrs_from_tag( 'form', '<form ' + form_attr_html[0][0] + '>' )[0]
    end

    def get_form_selects( html )
        selects = html.scan( /<select(.*?)>/ixm )

        elements = []
        selects.each_with_index {
            |select, i|
            elements[i] = Hash.new
            elements[i]['options'] =  get_form_selects_options( html )

            elements[i]['attrs'] =
                get_attrs_from_tag( 'select', 
                    '<select ' + select[0] + '/>' )[0]

        }

        elements
    end

    def get_form_selects_options( html )
        options = html.scan( /<option(.*?)>/ixm )

        elements = []
        options.each_with_index {
            |option, i|
            elements[i] =
                get_attrs_from_tag( 'option',
                    '<option ' + option[0] + '/>' )[0]

        }

        elements
    end

    def get_form_textareas( html )
        inputs = html.scan( /<textarea(.*?)>/ixm )

        elements = []
        inputs.each_with_index {
            |input, i|
            elements[i] =
                get_attrs_from_tag( 'textarea',
                    '<textarea ' + input[0] + '/>' )[0]
        }
        elements
    end

    #
    # Parses the attributes of input fields
    # @param  [String] html   HTML code for the form tag
    #
    # @return [Hash<Hash<String, String>>]
    #
    def get_form_inputs( html )
        inputs = html.scan( /<input(.*?)>/ixm )

        elements = []
        inputs.each_with_index {
            |input, i|
            elements[i] =
                get_attrs_from_tag( 'input',
                    '<input ' + input[0] + '/>' )[0]
        }

        elements
    end

    #
    # Gets attributes from HTML code of a tag
    #
    # @param  [String] tag    tag name (a, form, input)
    # @param  [String] html   HTML code for the form tag
    #
    # @return [Array<Hash<String, String>>]
    #
    def get_attrs_from_tag( tag, html )
        doc = Nokogiri::HTML( html )

        elements = []
        doc.search( tag ).each_with_index {
            |element, i|

            elements[i] = Hash.new

            element.each {
                |attribute|
                elements[i][attribute[0].downcase] = attribute[1]
            }

        }
        elements
    end

    # Extracts elements by name from HTML document
    #
    # @param [String] name 'form', 'a', 'div', etc.
    # @param  [String] html
    #
    # @return [Array<Hash <String, String> >] of elements
    #
    def get_elements_by_name( name, html )

        doc = Nokogiri::HTML( html )

        elements = []
        doc.search( name ).each_with_index do |input, i|

            elements[i] = Hash.new
            input.each {
                |attribute|
                elements[i][attribute[0]] = attribute[1]
            }
    
            input.children.each {
                |child|
                child.each{
                    |attribute|
                    elements[i][attribute[0]] = attribute[1]
                }
            }

        end rescue []

        return elements
    end

    #
    # Converts relative URL *link* into an absolute URL based on the
    # location of the page
    #
    # @param [String] link
    #
    # @return [String]
    #
    def to_absolute( link )

        begin
            if URI.parse( link ).host
                return link
            end
        rescue Exception => e
            return nil if link.nil?
            #      return link
        end

        # remove anchor
        link = URI.encode( link.to_s.gsub( /#[a-zA-Z0-9_-]*$/, '' ) )

        begin
            relative = URI(link)
            url = URI.parse( @url )

            absolute = url.merge(relative)

            absolute.path = '/' if absolute.path.empty?
        rescue Exception => e
            return
        end

        return absolute.to_s
    end

end
end
