module KyotoIndex
  module Search
    class << self
      def included(klass)
        # The index options for all indexed fields
        klass.instance_variable_set('@index_config', {})
        klass.send :include, InstanceMethods
        klass.extend ClassMethods
      end
    end

    module ClassMethods
      
      DEFAULT_STOP_WORDS = %w(& a able about across after all almost also am among an and any are as at be because been but by can cannot could dear did do does either else ever every for from get got had has have he her hers him his how however i if in into is it its just least let like likely may me might most must my neither no nor not of off often on only or other our own rather said say says she should since so some than that the their them then there these they this tis to too twas us wants was we were what when where which while who whom why will with would yet you your)
      
      attr_reader :index_config
      
      # Specify one or more attributes to index.
      # @overload add_index(attributes, options={})
      # @param [Array] attributes a list of one or more attributes/fields
      # @param [Hash] options controls how the specified fields are indexed
      # @options options [Integer] :ngram (1) The maximum length of sequential words to index
      # @options options [Integer] :minlength (2) The minimum word length to index
      # @options options [Regexp] :split (/\s+/) A regular expression defining how to split the text
      # @options options [Array] :stopwords A list of words that should be excluded from the index
      # @options options [Symbol] :db (:default) The name of the database (must be configured) to store the index for this field
      # @example add_index :foo, :bar, :ngram => 5, :db => :my_in_memory_db
      def add_index(*args)
        options = args.last.is_a?(::Hash) ? args.pop : {}
        options[:ngram] ||= 1
        options[:minlength] ||= 2
        options[:split] ||= /\s+/
        options[:stopwords] ||= DEFAULT_STOP_WORDS
        options[:db] ||= :default
        args.each do |attribute|
          index_config[attribute.to_sym] = options
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
          terms.each do |t|
            indices[t] += (field_results[key_for(field, t)] || [])
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
        keys = terms.reduce([]) do |list, term|
          list << key_for(field, term)
        end
        get_bulk(keys, index_config[field][:db])
      end

      def indexed_fields
        index_config.keys
      end
      
      def kt(db = :default)
        KyotoIndex.databases[db]
      end
      
      def get_bulk(keys, db = :default)
        bulk=kt(db).get_bulk(keys)
        bulk.delete("num")
        bulk = bulk.reduce({}) do |hash, (k,v)|
          key = k.match("^_") ? k[1..-1] : k
          hash[key] = v
          hash
        end
        bulk
      end

      def set_bulk(recs, db = :default)
        kt(db).set_bulk(recs)
      end

      def index_keys_for(id, db = :default)
        kt(db).get("#{self.name}::#{id}")
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
        "#{self.name}:#{field.to_s}:#{term}"
      end

    end

    module InstanceMethods
      # Index the specified fields or all configured fields if none specified
      # @param [Array] fields the list of (configured) fields to index
      # @note This currently assumes the object has not been previously indexed
      def index(*fields)
        fields = self.class.indexed_fields if fields.empty?
        keys = []
        fields.each do |field|
          options = self.class.index_config[field]
          value = self.send(field)
          next if value.nil?
          values = nil
          if value.is_a?(Array)
            values = value.map {|s| options[:split] ? s.split(options[:split]) : s }.flatten
          else
            values = options[:split] ? value.split(options[:split]) : value
          end

          (1..options[:ngram]).each do |n|
            values.each_cons(n) do |seq|
              # We don't care about this ngram if it starts or ends with a stop word
              # The non-stop word portion of the string will already have been indexed
              # on a previous iteration. i.e., when n was smaller.
              next if options[:stopwords].any? { |x| [seq.first, seq.last].include? x }
              # Concatenate ngram components and remove non alphanum/whitespace chars.
              ngram = self.class.clean_term(seq.join(" "))
              next if ngram.length < options[:minlength]
              k = self.class.key_for(field, ngram)
              keys << k
            end
          end
          nil
        end

        # # Figure out the indexing plan
        # old_keys = index_keys
        # new_keys = keys - old_keys
        # del_keys = old_keys - keys
        # 
        # next if new_keys.empty? and del_keys.empty?

        # Add new indices
        store_at_keys(keys)

        # # Delete indexes no longer used
        # exec_pipelined_index_cmd(:srem, del_indexes)

        # # Replace our reverse map of indexes
        # redis.set reverse_index_key(field), indexes.join(';')
        nil
      end

      def reindex(*fields)
        index(fields)
      end

      def unindex(*fields)

      end

      private
      def index_keys
        self.class.index_keys_for(id)
      end

      def store_at_keys(keys)
        idx = self.class.get_bulk(keys)
        keys.each do |k|
          puts idx[k].inspect
          idx[k] = [] unless idx[k]
          idx[k] << id
          idx[k].uniq!
          puts "%%%%%%%%%%%% #{idx.inspect}" if k.match("method$")
        end
        self.class.set_bulk(idx)
        nil
      end
    end
  end
end