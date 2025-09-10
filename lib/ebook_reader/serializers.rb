# frozen_string_literal: true

module EbookReader
  module Infrastructure
    class JSONSerializer
      def ext = 'json'
      def manifest_filename = 'manifest.json'
      def dump_file(path, data) = File.write(path, JSON.generate(data))
      def load_file(path) = JSON.parse(File.read(path))
    end

    class MessagePackSerializer
      def ext = 'msgpack'
      def manifest_filename = 'manifest.msgpack'
      def dump_file(path, data) = File.binwrite(path, MessagePack.pack(data))
      def load_file(path) = MessagePack.unpack(File.binread(path))
    end
  end
end
