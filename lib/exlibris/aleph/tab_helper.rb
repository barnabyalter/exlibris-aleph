module Exlibris
  module Aleph
    require 'singleton'
    require 'yaml'
    # ==Overview
    # Exlibris::Aleph::TabHelper assumes a mount of Aleph tab files and provides
    # a way to access the various tab settings for patrons, patron_permissions,
    # items, item_permission (both by item status and by item processing status),
    # collections and pickup locations.
    # It also provides convenience methods for common tasks like getting the
    # pickup location for a given combination of item status, item process status
    # and borrower status or getting an item's web text.
    # To initialize Exlibris::Aleph::TabHelper call Exlibris::Aleph::TabHelper.init
    # in an initializer.
    class TabHelper
      extend Config::Attributes
      include Singleton
      attr_reader :updated_at
      @@alephe_tabs = {
        :sub_libraries => :TabSubLibrary
      }
      @@adm_tabs = {
        :patrons => :PcTabExpFieldExtended,
        :patron_permissions => :Tab31,
        :items => :TabWwwItemDesc,
        :item_permissions_by_item_status => :Tab15ByItemStatus,
        :item_permissions_by_item_process_status => :Tab15ByItemProcessStatus,
        :collections => :Tab40,
        :pickup_locations => :Tab37 }
      @@tabs = @@alephe_tabs.keys + @@adm_tabs.keys

      # Refreshes the yml files that are used to parse the tables.
      def self.refresh_yml
        mkdirs
        @@alephe_tabs.each do |key, klass|
          tab = Exlibris::Aleph::TabParser.const_get(klass).new(:aleph_library => "ALEPHE", :aleph_mnt_path => tab_path).to_h
          File.open( File.join(yml_path, "alephe", "#{key}.yml"), 'w' ) { |out| YAML.dump( tab, out ) } unless tab.empty?
        end
        @@adm_tabs.each do |key, klass|
          adms.each do |adm|
            tab = Exlibris::Aleph::TabParser.const_get(klass).new(:aleph_library => adm, :aleph_mnt_path => tab_path).to_h
            File.open( File.join(yml_path, adm, "#{key}.yml"), 'w' ) { |out| YAML.dump( tab, out ) } unless tab.empty?
          end
        end
      end

      # Make the necessary directories
      def self.mkdirs
        FileUtils.mkdir_p File.join(yml_path, "alephe")
        adms.each do |adm|
          FileUtils.mkdir_p File.join(yml_path, adm)
        end
      end

      # Private initialzize method for the singleton.
      def initialize
        raise ArgumentError.new("No tab path was specified.") if self.class.tab_path.nil?
        raise ArgumentError.new("No yml path was specified.") if self.class.yml_path.nil?
        raise ArgumentError.new("No refresh time was specified.") if self.class.refresh_time.nil?
        self.class.refresh_yml
        @@tabs.each { |tab|
          # Default to empty hash
          instance_variable_set("@#{tab}".to_sym, {})
          # Define reader w/ refresh
          self.class.send(:define_method, tab) {
            refresh if refresh?
            instance_variable_get("@#{tab}".to_sym)
          }
        }
        refresh
      end

      # Returns the sub library display text for the given sub library code
      def sub_library_text(code)
        sub_library = @sub_libraries[code]
        return sub_library[:text] unless sub_library.nil?
      end

      # Returns the ADM associated with the given sub library code
      def sub_library_adm(code)
        sub_library = @sub_libraries[code]
        return sub_library[:library] unless sub_library.nil?
      end

      # Returns an array of pickup locations based on the given params.
      # Available param keys are:
      #   :adm_library_code, :sub_library_code, :item_status_code,
      #   :item_process_status_code, :bor_status, :availability_status
      def item_pickup_locations(params)
        adm_locations = pickup_locations[params[:adm_library_code]]
        sub_locations = adm_locations[params[:sub_library_code]] unless adm_locations.nil?

        # First try the most specific
        item_locations = sub_locations[params[:item_status_code]] unless sub_locations.nil?
        item_procesing_locations = item_locations[params[:item_process_status_code]] unless item_locations.nil?
        borrower_locations = item_procesing_locations[params[:bor_status]] unless item_procesing_locations.nil?
        availability_locations = item_procesing_locations[params[:bor_status]] unless item_procesing_locations.nil?
        locations = (borrower_locations.has_key?(params[:availability_status])) ?
          borrower_locations[:availability_status] : borrower_locations["#"] unless borrower_locations.nil?
        return locations[:pickup_locations] unless locations.nil?

        # Wild card item status
        item_locations, item_procesing_locations, borrower_locations = nil, nil, nil
        item_locations = sub_locations["##"] unless sub_locations.nil?
        item_procesing_locations = item_locations[params[:item_process_status_code]] unless item_locations.nil?
        borrower_locations = item_procesing_locations[params[:bor_status]] unless item_procesing_locations.nil?
        locations = (borrower_locations.has_key?(params[:availability_status])) ?
          borrower_locations[:availability_status] : borrower_locations["#"] unless borrower_locations.nil?
        return locations[:pickup_locations] unless locations.nil?

        # Wild card item process status
        item_locations, item_procesing_locations, borrower_locations = nil, nil, nil
        item_locations = sub_locations[params[:item_status_code]] unless sub_locations.nil?
        item_procesing_locations = item_locations["##"] unless item_locations.nil?
        borrower_locations = item_procesing_locations[params[:bor_status]] unless item_procesing_locations.nil?
        locations = (borrower_locations.has_key?(params[:availability_status])) ?
          borrower_locations[:availability_status] : borrower_locations["#"] unless borrower_locations.nil?
        return locations[:pickup_locations] unless locations.nil?

        # Wild card item status and item process status
        item_locations, item_procesing_locations, borrower_locations = nil, nil, nil
        item_locations = sub_locations["##"] unless sub_locations.nil?
        item_procesing_locations = item_locations["##"] unless item_locations.nil?
        borrower_locations = item_procesing_locations[params[:bor_status]] unless item_procesing_locations.nil?
        locations = (borrower_locations.has_key?(params[:availability_status])) ?
          borrower_locations[:availability_status] : borrower_locations["#"] unless borrower_locations.nil?
        return locations[:pickup_locations] unless locations.nil?

        # Wild card patron status
        item_locations, item_procesing_locations, borrower_locations = nil, nil, nil
        item_locations = sub_locations[params[:item_status_code]] unless sub_locations.nil?
        item_procesing_locations = item_locations[params[:item_process_status_code]] unless item_locations.nil?
        borrower_locations = item_procesing_locations["##"] unless item_procesing_locations.nil?
        locations = (borrower_locations.has_key?(params[:availability_status])) ?
          borrower_locations[:availability_status] : borrower_locations["#"] unless borrower_locations.nil?
        return locations[:pickup_locations] unless locations.nil?

        # Wild card patron status and item status
        item_locations, item_procesing_locations, borrower_locations = nil, nil, nil
        item_locations = sub_locations["##"] unless sub_locations.nil?
        item_procesing_locations = item_locations[params[:item_process_status_code]] unless item_locations.nil?
        borrower_locations = item_procesing_locations["##"] unless item_procesing_locations.nil?
        locations = (borrower_locations.has_key?(params[:availability_status])) ?
          borrower_locations[:availability_status] : borrower_locations["#"] unless borrower_locations.nil?
        return locations[:pickup_locations] unless locations.nil?

        # Wild card patron status and item process status
        item_locations, item_procesing_locations, borrower_locations = nil, nil, nil
        item_locations = sub_locations[params[:item_status_code]] unless sub_locations.nil?
        item_procesing_locations = item_locations["##"] unless item_locations.nil?
        borrower_locations = item_procesing_locations["##"] unless item_procesing_locations.nil?
        locations = (borrower_locations.has_key?(params[:availability_status])) ?
          borrower_locations[:availability_status] : borrower_locations["#"] unless borrower_locations.nil?
        return locations[:pickup_locations] unless locations.nil?

        # Wild card everything
        item_locations, item_procesing_locations, borrower_locations = nil, nil, nil
        item_locations = sub_locations["##"] unless sub_locations.nil?
        item_procesing_locations = item_locations["##"] unless item_locations.nil?
        borrower_locations = item_procesing_locations["##"] unless item_procesing_locations.nil?
        locations = (borrower_locations.has_key?(params[:availability_status])) ?
          borrower_locations[:availability_status] : borrower_locations["#"] unless borrower_locations.nil?
        return locations[:pickup_locations] unless locations.nil?

        # Set the pickup location to default to the passed in sub library
        logger.warn(
            "Warning in #{self.class}. "+
            "Pickup locations not found. "+
            "Defaulting to Aleph item sub library, #{params[:sub_library_code]}.\n"+
            "Additional parameters:\n"+
            "\tADM library: #{params[:adm_library_code]}\n"+
            "\tSub library: #{params[:sub_library_code]}\n"+
            "\tItem status: #{params[:item_status_code]}\n"+
            "\tItem process status: #{params[:item_process_status_code]}\n"+
            "\tAvailability status: #{params[:availability_status]}\n"+
            "\tBorrower status: #{params[:bor_status]}\n"
          )
          return [params[:sub_library_code]]
      end

      # Returns collection text for the given params.
      # Available param keys are:
      #   :adm_library_code, :sub_library_code, :collection_code
      def collection_text(params)
        adm = collections[params[:adm_library_code]]
        sub = adm[params[:sub_library_code]] unless adm.nil?
        coll = sub[params[:collection_code]] unless sub.nil?
        return coll[:text] unless coll.nil?
      end

      # Returns web display text for the given params.
      # Available param keys are:
      #   :adm_library_code, :sub_library_code, :item_status_code, :item_process_status_code, :item_status, :item_process_status
      def item_web_text(params)
        adm = items[params[:adm_library_code]]
        item = (adm[params[:item_process_status]].nil?) ? adm[params[:item_status]] : adm[params[:item_process_status]] unless (params[:item_status].nil? and params[:item_process_status].nil?) or adm.nil?
        permissions = item_permissions(params) if item.nil?
        item = adm[permissions[:text]] unless permissions.nil? or adm.nil?
        return item[:web_text] unless item.nil?
        return permissions[:text] unless permissions.nil?
      end

      # Returns item permissions for the given params.
      # Available param keys are:
      #   :adm_library_code, :sub_library_code, :item_status_code, :item_process_status_code
      def item_permissions(params)
        item_permissions = {}
        # Item process statuses take precedent in Aleph, same here.
        if item_permissions.empty? and params[:item_process_status_code]
          adm_permissions =
            item_permissions_by_item_process_status[params[:adm_library_code]]
          sublibrary_permissions =
            adm_permissions[params[:sub_library_code]] unless adm_permissions.nil?
          item_permissions =
            sublibrary_permissions[params[:item_process_status_code]] unless sublibrary_permissions.nil?
        end
        # If we didn't find anything with the item process status, try the item status
        if item_permissions.empty? and params[:item_status_code]
          adm_permissions = item_permissions_by_item_status[params[:adm_library_code]]
          sublibrary_permissions =
            adm_permissions[params[:sub_library_code]] unless adm_permissions.nil?
          item_permissions =
            sublibrary_permissions[params[:item_status_code]] unless sublibrary_permissions.nil?
        end
      rescue => e
        logger.error(%Q{
          Error in #{self.class}.
          Returning empty item permissions.
          Parameters:
            ADM library: #{params[:adm_library_code]}
            Sub library: #{params[:sub_library_code]}
            Item status: #{params[:item_status_code]}
            Item process status: #{params[:item_process_status_code]}}.strip)
        logger.error("Error: \n\t#{e}")
      ensure
        return item_permissions
      end

      def refresh?
        return (@updated_at.nil? or @updated_at < refresh_time.call)
      end
      private :refresh?

      def refresh
        @@alephe_tabs.each_key do |tab|
          instance_variable_set("@#{tab}".to_sym, YAML.load_file(File.join(yml_path, "alephe", "#{tab}.yml")))
        end
        @@adm_tabs.each_key do |tab|
          adms.each do |adm|
            instance_variable_get("@#{tab}".to_sym)[adm] = 
              YAML.load_file(File.join(yml_path, adm, "#{tab}.yml"))
          end
        end
        # Delete irrelevant sub libraries from @sub_library
        @sub_libraries.delete_if {|key,value| irrelevant_sub_libraries.include? key }
        # Since we update the YAML files in a separate process, don't overwrite
        # unless everything got some valid data.
        @updated_at = Time.now() if successful_refresh?
      end
      private :refresh

      # Did the refresh actually work?
      def successful_refresh?
        # No "false" entries in alephe tab variables
        (@@alephe_tabs.keys.find { |tab| (not instance_variable_get("@#{tab}".to_sym))}.nil? and
          # AND no "false" entries in adm tab variables
          @@adm_tabs.keys.find{ |tab| adms.find { |adm| (not (instance_variable_get("@#{tab}".to_sym)[adm])) }}.nil?)
      end
      private :successful_refresh?

      # Since we update the YAML files in a separate process, we need to 
      # wait until we actually get some YAML to load it into the hash.
      def hash_from_yaml_file(file)
        yaml = YAML.load_file(file)
      end
      private :hash_from_yaml_file

      def adms
        @adms ||= self.class.adms
      end

      def yml_path
        @yml_path ||= self.class.yml_path
      end
      private :yml_path

      def refresh_time
        @refresh_time ||= self.class.refresh_time
      end
      private :refresh_time

      def logger
        @logger ||= self.class.logger
      end
      private :logger

      def irrelevant_sub_libraries
        @irrelevant_sub_libraries ||= self.class.irrelevant_sub_libraries
      end
      private :irrelevant_sub_libraries
    end
  end
end