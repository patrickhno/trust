# Copyright (c) 2012 Bingo Entreprenøren AS
# Copyright (c) 2012 Teknobingo Scandinavia AS
# Copyright (c) 2012 Knut I. Stenmark
# Copyright (c) 2012 Patrick Hanevold
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

module Trust
  module Controller
    class Resource
      delegate :logger, :to => Rails
      attr_reader :properties, :params, :action
      attr_reader :info, :parent_info, :relation

      def initialize(controller, properties, action_name, params, request)
        @action = action_name.to_sym
        
        @controller, @properties, @params = controller, properties, params
        @info = extract_resource_info(properties.model_name, params)
        if properties.has_associations?
          @parent_info = extract_parent_info(properties.associations, params, request)
        end
        @relation = @info.relation(@parent_info)
      end
      
      # Controller accessors
      def instance=(instance)
        @controller.instance_variable_set(:"@#{instance_name}", instance)
      end
      
      def instance
        @controller.instance_variable_get(:"@#{instance_name}")
      end
      
      def instance_params
        info.params
      end
      
      def parent=(instance)
        @controller.instance_variable_set(:"@#{parent_name}", instance)
      end

      def parent
        @controller.instance_variable_get(:"@#{parent_name}")
      end
      
      def instances=(instances)
        @controller.instance_variable_set(:"@#{plural_instance_name}", instances)
      end

      def instances
        @controller.instance_variable_get(:"@#{plural_instance_name}")
      end

      def instantiated
        instances || instance
      end

      def klass
        info.klass
      end

      def load
        self.parent = parent_info.object if parent_info
        if properties.new_actions.include?(action)
          logger.debug "Setting new: info.params: #{info.params.inspect}"
          self.instance ||= relation.new(info.params)
          @controller.send(:build, action) if @controller.respond_to?(:build)
        elsif properties.member_actions.include?(action)
          logger.debug "Finding parent: #{parent.inspect}, relation: #{relation.inspect}"
          self.instance ||= relation.find(params[:id])
          @controller.send(:build, action) if @controller.respond_to?(:build)
        end # other outcome would be collection actions
      end
      
      def instance_name
        info.name
      end
      
      def plural_instance_name
        info.plural_name
      end
      
      def parent_name
        parent_info && parent_info.name
      end
      
      
    private
      def extract_resource_info(model_name, params)
        ResourceInfo.new(model_name, params)
      end
      
      def extract_parent_info(associations, params, request)
        ParentInfo.new(associations, params, request)
      end      
    end

    # Resorce resolves information about the resource accessed in action controller
    # This is automatically included in ActionController as long as the method resource is accessed
    #
    # Examples in PeopleController (simple case)
    # ===
    #   resource.klass => Person
    #   resource.params => {:person => {...}}       # fetches the parameters for the resource
    #   resource.name => :person
    #   resource.plural_name => :people
    #   resource.path => 'people'                   # this is the controller_path
    #
    # Examples in Lottery::AssignmentsController (with name space)
    # ===
    #   resource.klass => Lottery::Assignment
    #   resource.params => {:lottery_assignment => {...}}
    #   resource.name => :lottery_assignment
    #   resource.plural_name => :lottery_assignments
    #   resource.path => 'lottery/assignments'      # this is the controller_path
    #
    # Examples in ArchiveController (with inheritance) 
    # Assumptions on routes:
    #   resources :archives
    #   resources :secret_acrvives, :controller => :archives
    #   resources :public_acrvives, :controller => :archives
    # examples below assumes that the route secret_arcives is being accessed at the moment
    # ===
    #   resource.klass => Archive
    #   resource.params => {:secret_archive => {...}}
    #   resource.name => :archive
    #   resource.plural_name => :archives
    #   resource.path => 'archive'                   # this is the controller_path
    #   resource.real_class => SecretArchive         # Returns the real class which is accessed at the moment
    #
    
    class Resource::Info
      attr_reader :klass, :params, :name, :path, :real_class
      
      def params
        @data
      end
   
    protected
      def var_name(klass)
        klass.to_s.underscore.tr('/','_').to_sym
      end
    end
    

    class Resource::ResourceInfo < Resource::Info

      def initialize(model_name, params)
        @path, params = model_name, params
        @klass = model_name.to_s.classify.constantize
        @name = model_name.to_s.singularize.underscore.gsub('/','_').to_sym
        ptr = @klass.descendants.detect do |c|
          params.key? var_name(c)
        end || @klass
        @real_class = ptr
        @data = params[var_name(ptr)]
      end

      def plural_name
        @plural_name ||= path.underscore.tr('/','_').to_sym
      end

      # returns an accessor for association. Tries with full name association first, and if that does not match, tries the demodularized association.
      #
      # Explanation:
      #   Assuming 
      #     resource is instance of Lottery::Package #1 (@lottery_package)
      #     association is Lottery::Prizes
      #     if association is named lottery_prizes, then that association is returned
      #     if association is named prizes, then that association is returned
      #   
      def relation(associated_resource)
        if associated_resource && associated_resource.object
          name = associated_resource.as || plural_name
          associated_resource.klass.reflect_on_association(name) ? 
            associated_resource.object.send(name) : associated_resource.object.send(klass.to_s.demodulize.underscore.pluralize)
        else
          klass
        end
      end
    end

    class Resource::ParentInfo < Resource::Info
      attr_reader :object,:as
      def initialize(resources, params, request)
        ptr = resources.detect do |r,as|
          @klass = classify(r)
          @as = as
          ([@klass] + @klass.descendants).detect do |c|
            @name = c.to_s.underscore.tr('/','_').to_sym
            unless @id = request.symbolized_path_parameters["#{@name}_id".to_sym]
              # see if name space handling is necessary
              if c.to_s.include?('::')
                @name = c.to_s.demodulize.underscore.to_sym
                @id = request.symbolized_path_parameters["#{@name}_id".to_sym]
              end
            end
            @id
          end
          @id
        end
        if ptr
          @object = @klass.find(@id)
        else
          @klass = @name = nil
        end
        @data = params[var_name(ptr)]
      end

      def object?
        !!@object
      end

      def real_class
        @object && @object.class
      end
    private
      def classify(resource)
        case resource
        when Symbol, String
          resource.to_s.classify.constantize
        else
          resource
        end
      end
    end
  end
end
