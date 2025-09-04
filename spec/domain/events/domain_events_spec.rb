# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Domain Events' do
  it 'serializes bookmark events' do
    bm = double('Bookmark', chapter_index: 1, line_offset: 2)
    evt = EbookReader::Domain::Events::BookmarkAdded.new(book_path: '/p.epub', bookmark: bm)
    h = evt.to_h
    expect(h[:event_type]).to eq('BookmarkAdded')
    expect(h[:data][:book_path]).to eq('/p.epub')

    evt2 = EbookReader::Domain::Events::BookmarkRemoved.new(book_path: '/p.epub', bookmark: bm)
    expect(evt2.to_h[:event_type]).to eq('BookmarkRemoved')

    evt3 = EbookReader::Domain::Events::BookmarkNavigated.new(book_path: '/p.epub', bookmark: bm)
    expect(evt3.to_h[:event_type]).to eq('BookmarkNavigated')
  end

  it 'serializes annotation events' do
    ann = { 'id' => '1', 'note' => 'n' }
    add = EbookReader::Domain::Events::AnnotationAdded.new(book_path: '/p.epub', annotation: ann)
    expect(add.to_h[:event_type]).to eq('AnnotationAdded')

    upd = EbookReader::Domain::Events::AnnotationUpdated.new(book_path: '/p.epub', annotation_id: '1', old_note: 'o', new_note: 'n')
    expect(upd.to_h[:data][:annotation_id]).to eq('1')

    rem = EbookReader::Domain::Events::AnnotationRemoved.new(book_path: '/p.epub', annotation_id: '1', annotation: ann)
    expect(rem.to_h[:data][:annotation_id]).to eq('1')
  end

  it 'validates required and typed attributes and roundtrips from hash' do
    TestEvent = Class.new(EbookReader::Domain::Events::BaseDomainEvent) do
      required_attributes :user_id, :action
      typed_attributes user_id: String
    end
    expect { TestEvent.new(user_id: 'u1', action: 'login') }.not_to raise_error
    expect { TestEvent.new(action: 'login') }.to raise_error(ArgumentError)
    expect { TestEvent.new(user_id: 123, action: 'login') }.to raise_error(TypeError)

    evt = TestEvent.new(user_id: 'u2', action: 'logout')
    restored = TestEvent.from_h(evt.to_h)
    expect(restored.of_type?(TestEvent.name.split('::').last)).to be true
  end
end
