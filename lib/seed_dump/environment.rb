class SeedDump
  module Environment

    def dump_using_environment(env = {})
      Rails.application.eager_load!

      models = if env['MODEL'] || env['MODELS']
                 (env['MODEL'] || env['MODELS']).split(',').collect {|x| x.strip.underscore.singularize.camelize.constantize }
               else
                 ActiveRecord::Base.descendants.select do |model|
                   (model.to_s != 'ActiveRecord::SchemaMigration') && \
                    model.table_exists? && \
                    model.exists?
                 end
               end

      append = (env['APPEND'] == 'true')

      models, t_info = order_models(models)

      # remove unwanted models
      if env['IGNORE']
        x = env['IGNORE'].split(',').collect { |m| m.camelize.constantize }
        x.each { |m| models.delete(m) }
      end

      models.each do |model|
        model = model.limit(env['LIMIT'].to_i) if env['LIMIT']

        SeedDump.dump(model,
                      append: append,
                      batch_size: (env['BATCH_SIZE'] ? env['BATCH_SIZE'].to_i : nil),
                      exclude: (env['EXCLUDE'] ? env['EXCLUDE'].split(',').map {|e| e.strip.to_sym} : nil),
                      file: (env['FILE'] || 'db/seeds.rb'),
                      clean: (env['CLEAN'] || false),
                      model: model, # looks like duplicated info but as options make it all the way
                      # to dump_record it's more convenient to put it here
                      tbl_info: t_info)

        append = true
      end
    end

    def order_models(models)
      process = []
      final = []
      tables = {}
      models.each do |model|
        rel = model.reflect_on_all_associations(:belongs_to)
        if rel.length > 0 # if table references other(s) it should be rechecked
          process << model
        else # standalone table or table referenced by other(s)
          final << model
        end
        # get info about unique identifiers
        # and referenced tables
        if !tables.has_key?(model)
          x = model.validators.select {|v| v if v.class==ActiveRecord::Validations::UniquenessValidator }
          if x.length > 0
            tables[model] = {unique: x[0].attributes}
            x[0].options[:scope].each { |s| tables[model][:unique].append(s) } if x[0].options.has_key?(:scope)
          else
            tables[model] = {unique: []}
          end
          tables[model][:fks] = {}

          rel.each do |a|
            if a.options[:polymorphic]
              tables[model][:fks][a.foreign_key] = model.all.each.map { |e| e.attached_to.class }.uniq
            elsif a.options[:class_name]
              tables[model][:fks][a.foreign_key] = a.options[:class_name].classify.constantize
            else
              tables[model][:fks][a.foreign_key] = a.plural_name.classify.constantize
            end
          end
        end
      end

      begin
        del = []
        process.each do |p|
          if check_relations(final, tables[p])
            final << p # put here tables with reference to ones already in final array
            del << p
          end
        end
        del.each { |d| process.delete(d) }
        # if del.length > 0 it means additional table was added to final list
        # we shouldn't check length of process because it could happen there is a circular reference
        # among some tables so we could end up in never ending loop
      end while del.length > 0
      # now the question is what to do with remaining tables in process
      # if there is any
      # this is just a very bad implementation but no to have something 
      # forgotten
      final.concat(process) if process.length > 0

      return final, tables
    end

    def check_relations(final, check)
      check[:fks].each do |a, v|
        if v.class == Array
          v.each do |aa|
            return false if not final.include? aa
          end
        else
          return false if not final.include? v
        end
      end

      true
    end

  end
end

