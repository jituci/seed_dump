class SeedDump

  module DumpMethods
    include Enumeration

    def dump(records, options = {})
      return nil if records.count == 0

      io = open_io(options)

      write_records_to_io(records, io, options)

      ensure
        io.close if io.present?
    end

    private

    def dump_record(record, options)
      attribute_strings = []

      options[:exclude] ||= [:id, :created_at, :updated_at]

      # We select only string attribute names to avoid conflict
      # with the composite_primary_keys gem (it returns composite
      # primary key attribute names as hashes).
      record.attributes.select {|key| key.is_a?(String) }.each do |attribute, value|
        attribute_strings << dump_attribute_new(attribute, value, options, record) unless options[:exclude].include?(attribute.to_sym)
      end

      "{#{attribute_strings.join(", ")}}"
    end

    def get_foreign_attr(model, tbls, attr, value, record)
      # model
      # fks - class of referenced model
      # tbls - overall info about models
      #

      model = record[attr.to_s.sub(/_[^_]+$/, '_type')].classify.constantize if model.class == Array

      out = "#{attr}: #{model}.find_by("
      
      # get list of unique attributes for referenced class
      uniq = tbls[model][:unique]

      uniq.each do |u|
        if value
          # if it points to another foreign_key do it again
          if tbls[model][:fks].has_key?(u.to_s)
            out << get_foreign_attr(tbls[model][:fks][u.to_s], tbls, u, model.find(value)[u], model.find(value))
          else
            out << "#{u}: #{value_to_s(model.find(value)[u])},"
          end
        else
          out << "#{u}: #{value_to_s(nil)},"
        end
      end

      out[0..-2] + ")[:#{model.primary_key}],"
    end

    def dump_attribute_new(attribute, value, options, record)
      if value and options[:tbl_info][options[:model]][:fks].has_key?(attribute)
        # get referenced class
        fks = options[:tbl_info][options[:model]][:fks][attribute]
        get_foreign_attr(fks, options[:tbl_info], attribute, value, record)[0..-2]
      else
        "#{attribute}: #{value_to_s(value)}"
      end
    end

    def value_to_s(value)
      value = case value
              when BigDecimal
                value.to_s
              when Date, Time, DateTime
                value.to_s(:db)
              when Range
                range_to_string(value)
              else
                value
              end

      value.inspect
    end

    def range_to_string(object)
      from = object.begin.respond_to?(:infinite?) && object.begin.infinite? ? '' : object.begin
      to   = object.end.respond_to?(:infinite?) && object.end.infinite? ? '' : object.end
      "[#{from},#{to}#{object.exclude_end? ? ')' : ']'}"
    end

    def open_io(options)
      if options[:file].present?
        mode = options[:append] ? 'a+' : 'w+'

        File.open(options[:file], mode)
      else
        StringIO.new('', 'w+')
      end
    end

    def write_records_to_io(records, io, options)
      io.write("#{model_for(records)}.delete_all\n") if options[:clean]
      io.write("#{model_for(records)}.create!([\n  ")

      enumeration_method = if records.is_a?(ActiveRecord::Relation) || records.is_a?(Class)
                             :active_record_enumeration
                           else
                             :enumerable_enumeration
                           end

      send(enumeration_method, records, io, options) do |record_strings, last_batch|
        io.write(record_strings.join(",\n  "))

        io.write(",\n  ") unless last_batch
      end

      io.write("\n])\n\n")

      if options[:file].present?
        nil
      else
        io.rewind
        io.read
      end
    end

    def model_for(records)
      if records.is_a?(Class)
        records
      elsif records.respond_to?(:model)
        records.model
      else
        records[0].class
      end
    end

  end
end

