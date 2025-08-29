# frozen_string_literal: true

module EbookReader
  module Services
    # TEMPORARY: Compatibility wrapper for Services::LayoutService
    # This delegates to the domain service until all references are migrated
    class LayoutService
      def self.calculate_metrics(width, height, view_mode)
        container = Domain::ContainerFactory.create_default_container
        layout_service = container.resolve(:layout_service)
        layout_service.calculate_metrics(width, height, view_mode)
      end

      def self.adjust_for_line_spacing(height, line_spacing)
        container = Domain::ContainerFactory.create_default_container
        layout_service = container.resolve(:layout_service)
        layout_service.adjust_for_line_spacing(height, line_spacing)
      end

      def self.calculate_center_start_row(content_height, lines_count, line_spacing)
        container = Domain::ContainerFactory.create_default_container
        layout_service = container.resolve(:layout_service)
        layout_service.calculate_center_start_row(content_height, lines_count, line_spacing)
      end
    end
  end
end