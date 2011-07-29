require 'kyototycoon'
require 'kyotoindex/search'
module KyotoIndex
  
  mattr_accessor :databases
  @@databases = {}

  def self.setup(&block)
    yield self
    add_db :default unless @@databases[:default]
  end

  def self.add_db name, options={}
    KyotoTycoon.configure(name) do |kt|
      kt.db = options[:db] || '*'
    end

    kt = KyotoTycoon.create(name)
    kt.serializer = options[:serializer] || :default

    @@databases[name] = kt
    kt
  end
  
  def self.set_default_db name, options={}
    @@databases[:default] = @@databases[name] || add_db(name, options)
  end

end
