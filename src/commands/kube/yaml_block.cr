require "yaml"

# Re-emits stdlib YAML docs with multiline string values forced as literal block scalars (`|`).
module Crux::Kube::YamlBlock
  # Re-emits a parsed stdlib YAML doc as a string, focing any multiline string scalars to LITERAL block style (`|`).
  #
  # All other scalars keep their default style.
  def self.emit(any : YAML::Any) : String
    YAML.build do |bldr|
      emit_node(any, bldr)
    end
  end

  # Recursively walks a YAML::Any node, driving the builder.
  # Mappings and sequences recurse, string scalars containing newlines are emitted as literal block scalars. Everything else keeps default scalar style.
  private def self.emit_node(any : YAML::Any, builder : YAML::Builder) : Nil
    case raw = any.raw
    when Hash
      builder.mapping do
        raw.each do |k, v|
          emit_node(k, builder)
          emit_node(v, builder)
        end
      end
    when Array
      builder.sequence do
        raw.each { |item| emit_node(item, builder) }
      end
    when String
      if raw.includes?('\n')
        builder.scalar(raw, style: YAML::ScalarStyle::LITERAL)
      else
        builder.scalar(raw)
      end
    when Nil
      builder.scalar(nil)
    else
      builder.scalar(raw)
    end
  end
end
