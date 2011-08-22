module KyotoIndex
  module Search
    class << self
      def included(klass)
        # The index options for all indexed fields
        klass.instance_variable_set('@index_config', {})
        klass.instance_variable_set('@field_map', {})
        klass.send :include, InstanceMethods
        klass.extend ClassMethods
      end
    end

    module ClassMethods
      
      attr_reader :index_config
      
      # The field map is used to optimise indexing and querying.
      # Since most of the time most fields will be configured to use the
      # same database, it makes sense to group/batch operations for these fields.
      attr_reader :field_map
      
      # Specify one or more attributes to index.
      # @overload add_index(attributes, options={})
      # @param [Array] attributes a list of one or more attributes/fields
      # @param [Hash] options controls how the specified fields are indexed
      # @options options [Integer] :ngram (1) The maximum length of sequential words to index
      # @options options [Integer] :minlength (2) The minimum word length to index
      # @options options [Regexp] :split (/\s+/) A regular expression defining how to split sentences into terms
      # @options options [Regexp] :sentence_split (/[.?!;](?: |$)/) A regular expression defining how to split text into sentences
      # @options options [Array] :stopwords A list of words that should be excluded from the index
      # @options options [Symbol] :db (:default) The name of the database (must be configured) to store the index for this field
      # @example add_index :foo, :bar, :ngram => 5, :db => :my_in_memory_db
      def add_index(*args)
        options = args.last.is_a?(::Hash) ? args.pop : {}
        options[:ngram] ||= 1
        options[:weight] ||= 1.0
        options[:minlength] ||= 2
        options[:split] ||= /\s+/
        options[:sentence_split] ||= /[.?!;](?: |$)/
        options[:stopwords] ||= KyotoIndex.stopwords
        options[:db] ||= :default
        args.each do |attribute|
          index_config[attribute.to_sym] = options
          field_list = field_map[options[:db]] || []
          field_list << attribute.to_sym
          field_map[options[:db]] = field_list
        end
      end

      # Retrieve objects that match the specified search terms
      # @overload search(terms, fields)
      # @param [Array] terms a list of search terms
      # @param [Hash] fields confine the search to the specified fields
      # @options fields [Array] :fields (All indexed fields) a list of fields
      # @example search("social networks", "machine learning", :fields => [:title, :body])
      # @note All search terms must be found, but they need not occur together in the same fields
      # @overload search(query)
      # @param [Hash] query a hash of field/attribute names mapped to lists of search terms
      # @example search(:title => ["machine learning"], :body => ["machine learning", "social networks"])
      # @note Each search term *must* be found in the corresponding field
      def search(*args)
        if args.first.is_a?(String)
          fields = args.last.is_a?(Hash) ? (args.pop[:fields] || indexed_fields) : indexed_fields
          search_results = find_in_any_field(args, fields)
        elsif args.first.is_a?(Hash)
          search_results = find_in_fields(args.first)
        end
        if search_results and not search_results.empty?
          find(*search_results)
        else
          nil
        end
      end

      def find_in_any_field(raw_terms, fields)

        # Need to do this term by term, then intersect the results
        results = fields.reduce(Hash.new([])) do |indices, field|
          terms = raw_terms.map { |t| prepare_term(field, t) }
          field_results = search_field_for(field, terms)
          
          field_results.each do |k, v|
            indices[k.split(":").last] += v.keys
          end
            
          indices
        end

        values = results.values
        
        found = nil
        
        if(values.length > 0)
          found = values.reduce(values.first.dup) do |intersection, result|
            intersection = intersection & result
          end
        end

        found

      end

      def find_in_fields(query)
        results = query.reduce({}) do |hash, (field, raw_terms)|
          terms = raw_terms.map { |t| prepare_term(field, t) }
          r = search_field_for(field, terms)
          return nil unless r.length == terms.length
          hash.merge!(r)
          hash
        end

        values = results.values

        found = values.reduce(values.first.dup) do |intersection, result|
          intersection = intersection & result
        end

        found

      end

      def search_field_for(field, terms)
        term_keys = terms.map {|t| key_for(field, t)}
        get_bulk(term_keys, index_config[field][:db])
      end

      def indexed_fields
        index_config.keys
      end
      
      def kt(db = :default)
        KyotoIndex.databases[db]
      end
      
      def get_bulk(keys, db = :default)
        kt(db).get_bulk(keys)
      end

      def set_bulk(recs, db = :default)
        kt(db).set_bulk(recs)
      end

      def summaries_for(ids, db = :meta)
        list = ids.map {|id| id.is_a? self ? "#{ki_namespace}:summary:#{id.id}" : "#{ki_namespace}:summary:#{id}" }
        kt(db).get_bulk(list)
      end

      def summary_for(id, db = :meta)
        kt(db).get("#{ki_namespace}:summary:#{id}")
      end
      
      def store_summary_for(id, summary, db = :meta)
        kt(db).set("#{ki_namespace}:summary:#{id}", summary)
      end
      
      def remove_summary_for(id, db = :meta)
        kt(db).remove("#{ki_namespace}:summary:#{id}")
      end
      
      def prepare_term(field, term)
        clean = clean_term(term)
        words = clean.split(index_config[field][:split])
        words = words.drop_while { |w| index_config[field][:stopwords].include? w }
        words = words.reverse.drop_while { |w| index_config[field][:stopwords].include? w }.reverse
        words.join(" ")
      end
      
      def clean_term(term)
        term.gsub(/[^\w\s]+/, '').gsub(/\s{2,}/, ' ').downcase
      end

      def key_for(field, term)
        "#{ki_namespace}:field:#{field.to_s}:#{term}"
      end
      
      def term_ids_for(terms, db = :meta)
        term_keys = terms.map {|t| "#{ki_namespace}:term_id:#{t}"}
        get_bulk(term_keys, db).values
      end
      
      def term_id_for(term, db = :meta)
        term_id = kt(db).get("#{ki_namespace}:term_id:#{term}")
        unless term_id
          term_id = kt(db).increment("#{ki_namespace}:next_term_id")
          kt(db).set("#{ki_namespace}:term_id:#{term}", term_id)
        end
        term_id.to_i
      end
      
      def ki_namespace
        @ki_namespace ||= "KyotoIndex:#{self.name}"
      end
    end

    module InstanceMethods
      # Index the specified fields or all configured fields if none specified
      # @param [Array] fields the list of (configured) fields to index
      # @note This currently assumes the object has not been previously indexed
      # Creates an index that looks like:
      # KyotoIndex:ModelName:field:field_name:term => {"term_id" => id, "index" => {doc_id1 => 0.2, doc_id2 => 0.12, doc_id3 => 0.09}}
      # KyotoIndex:ModelName:term_id:term => id
      # KyotoIndex:ModelName:next_term_id => num
      # KyotoIndex:ModelName:summary:id => {"terms" => {term_id => {field_name => freq}}, "total_words" => 651}
      def index(*field_list)
        fields_to_index = nil
        
        # Get a map of dbs to fields
        if field_list.empty?
          fields_to_index = self.class.field_map
        else
          fields_to_index = field_list.group_by {|f| self.class.index_config[f][:db]}
        end
        index_entries = {}
        doc_summary = {"terms" => {}, "total_words" => 0}
        
        fields_to_index.each do |db, fields|
          fields.each do |field|
            field_entries = Hash.new(0)
            options = self.class.index_config[field]
            value = self.send(field)
            next if value.nil?
            sentences = nil
            if value.is_a?(Array)
              sentences = value
            else
              sentences = options[:sentence_split] ? value.split(options[:sentence_split]) : [value]
            end
            
            sentence_terms = sentences.map {|s| options[:split] ? s.split(options[:split]) : [s]}
          
            term_count = sentence_terms.reduce(0) {|sum, st| sum += st.length}
            doc_summary["total_words"] += term_count
          
            sentence_terms.each do |terms|
              (1..options[:ngram]).each do |n|
                terms.each_cons(n) do |seq|
                  # We don't care about this ngram if it starts or ends with a stop word
                  # The non-stop word portion of the string will already have been indexed
                  # on a previous iteration. i.e., when n was smaller.
                  next if options[:stopwords].any? { |x| [seq.first, seq.last].include? x }
                  # Concatenate ngram components and remove non alphanum/whitespace chars.
                  ngram = self.class.clean_term(seq.join(" "))
                  next if ngram.length < options[:minlength]
              
                  field_entries[ngram] += 1

                end
              end
            end
          
            field_entries.each do |ngram, count|
              key = self.class.key_for(field, ngram)
              term_id = self.class.term_id_for(ngram)
              freq = count / term_count.to_f
              index_entries[key] = {:term_id => term_id, :freq =>  freq}
              term_vector = doc_summary["terms"][term_id] || {}
              term_vector[field] = freq
              doc_summary["terms"][term_id] = term_vector
            end
          end
          # Store the batch
          store(index_entries, db)
        end

        # # Figure out the indexing plan
        # old_keys = index_keys
        # new_keys = keys - old_keys
        # del_keys = old_keys - keys
        # 
        # next if new_keys.empty? and del_keys.empty?

        # Add new indices
        store_summary(doc_summary)

        # # Delete indexes no longer used
        # exec_pipelined_index_cmd(:srem, del_indexes)

        # # Replace our reverse map of indexes
        # redis.set reverse_index_key(field), indexes.join(';')
        nil
      end

      def reindex(*fields)
        index(fields)
      end

      # This needs to be fixed to cater to different dbs for each field
      # def unindex()
      #   idx = self.class.get_bulk(index_keys)
      #   idx.each do |k, entries|
      #     entries.delete(id)
      #   end
      #   self.class.remove_summary_for(id)
      # end

      def summary
        self.class.summary_for(id)
      end

      private
      
      def store(entries, db = :default)
        idx = self.class.get_bulk(entries.keys, db)
        entries.each do |k, entry|
          idx[k] = {"term_id" => entry[:term_id], "index" => {}} unless idx[k]
          idx[k]["index"][id] = entry[:freq]
        end
        self.class.set_bulk(idx, db)
        nil
      end
      
      def store_summary(doc_summary, db = :meta)
        self.class.store_summary_for(id, doc_summary, db)
      end
    end
  end
end