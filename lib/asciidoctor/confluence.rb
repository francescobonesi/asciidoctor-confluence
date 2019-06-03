require_relative 'confluence/version'
require_relative './page'
require_relative './confluence_api'

require 'asciidoctor'
require 'asciidoctor-diagram'
require 'faraday'
require 'json'


module Asciidoctor
  module Confluence

    class Publisher
      SUCCESSFUL_CREATE_RESULT = 'The page has been successfully created. It is available here: '
      SUCCESSFUL_UPDATE_RESULT = 'The page has been successfully updated. It is available here: '
      SUCCESSFUL_ADDED_ATTACHMENT = 'The attachment has been successfully created. Image: '
      SUCCESSFUL_UPDATED_ATTACHMENT = 'The attachment has been successfully updated. Image: '
      ERROR_IN_ATTACHMENTS = 'Error in creating/updating attachment: '

      def initialize(options)
        @confluence_options = options[:confluence]
        @asciidoctor_options = options
        @asciidoctor_options[:requires] = ['asciidoctor-diagram']
        @asciidoctor_options[:to_file] = false
        @asciidoctor_options[:header_footer] = false
        @asciidoctor_options[:attributes] = ['experimental']
        @url_for_images = @confluence_options[:host] + "/download/thumbnails/" + @confluence_options[:page_id] + "/"
        
        if (options[:input_files].is_a? ::Array) && (options[:input_files].length == 1)
          @input_file = options[:input_files][0]
        else
          @input_file = options[:input_files]
        end
      end

      def publish

        @type = @confluence_options[:type]

        if @type == 'page'

          document = Asciidoctor.convert_file @input_file, @asciidoctor_options
          document = document.gsub(/(<img.*)>/, '\1/>') # close all opened img tags in html document
          document = document.gsub(/"(.*.png)"/, '"' + @url_for_images + '\1"') # replace all png refs to have conflucence download url for attachments
          
          page = Page.new @confluence_options[:space_key], @confluence_options[:title], document, @confluence_options[:page_id]
          api = ConfluenceAPI.new @confluence_options, page
          begin
            response = api.create_or_update_page @confluence_options[:update], @confluence_options[:page_id]
  
            response_body = JSON.parse response.body
            if response.success?
              url = response_body['_links']['base']+response_body['_links']['webui']
  
              if @confluence_options[:update]
                $stdout.puts SUCCESSFUL_UPDATE_RESULT + url
              else
                $stdout.puts SUCCESSFUL_CREATE_RESULT + url
              end
  
              return 0
  
            else
              action = get_action_string
              show_error action, response_body['message']
              return 1
            end
          rescue Exception => e
            show_error get_action_string, e.message
          end

        elsif @type == 'images'
          
          api = ConfluenceAPI.new @confluence_options

          if @confluence_options.key?(:images)
            @confluence_options[:images].split(',').each do |image|

              response = api.create_attachment @confluence_options[:page_id], image
              
              if response.success?
                $stdout.puts response.body
                $stdout.puts SUCCESSFUL_ADDED_ATTACHMENT + image
              else
                response = api.update_attachment @confluence_options[:page_id], image
                if response.success?
                  $stdout.puts response.body
                  $stdout.puts SUCCESSFUL_UPDATED_ATTACHMENT + image
                else
                  $stdout.puts ERROR_IN_ATTACHMENTS + image
                end
              end
              
            end
          end

        else
          puts 'Type ' + @type + ' is not allowed'
        end

        return 0

      end

      def get_action_string
        @confluence_options[:update] ? action = 'updated' : action = 'created'
        action
      end

      def show_error(action, message)
        $stderr.puts "An error occurred, the page has not been #{action} because:\n#{message}"
      end
    end
  end
end
