describe Neo4j::Migrations::Helpers do
  include described_class
  include Neo4j::Migrations::Helpers::Schema
  include Neo4j::Migrations::Helpers::IdProperty

  before do
    Neo4j::Session.current.close if Neo4j::Session.current
    create_session

    clear_model_memory_caches
    delete_db

    stub_active_node_class('Book') do
      property :name, constraint: :unique
      property :author_name, index: :exact
    end

    Book.create!(name: 'Book1')
    Book.create!(name: 'Book2')
    Book.create!(name: 'Book3')
  end

  describe '#remove_property' do
    it 'removes a property' do
      remove_property :Book, :name
      expect(Book.all(:n).pluck('n.title')).to eq([nil, nil, nil])
    end
  end

  describe '#rename_property' do
    it 'renames a property' do
      rename_property :Book, :name, :title
      expect(Book.all(:n).pluck('n.title')).to include('Book1', 'Book2', 'Book3')
    end

    it 'fails to remove when destination property is already defined' do
      expect { rename_property :Book, :author_name, :name }.to raise_error(
        'Property `name` is already defined in `Book`. To overwrite, call `remove_property(:Book, :name)` before this method.')
    end
  end

  describe '#drop_nodes' do
    it 'drops all nodes given a label' do
      drop_nodes :Book
      expect(Book.all.count).to eq(0)
    end
  end

  describe '#add_labels' do
    it 'adds labels to a node' do
      add_labels :Book, [:Item, :Readable]
      expect(Book.first.labels).to eq([:Book, :Item, :Readable])
    end
  end

  describe '#remove_labels' do
    it 'removes labels from a node' do
      add_label :Book, :Item
      expect(Book.first.labels).to eq([:Book, :Item])
      remove_label :Book, :Item
      expect(Book.first.labels).to eq([:Book])
    end
  end

  describe '#rename_label' do
    it 'renames a label' do
      execute 'CREATE (n:`Item` { name: "Lorem Ipsum" })'
      rename_label :Item, :Book
      expect(Book.find_by(name: 'Lorem Ipsum')).not_to be_nil
    end
  end

  describe '#execute' do
    it 'executes plan cypher query with parameters' do
      expect do
        execute 'MATCH (b:`Book`) WHERE b.name = {book_name} DELETE b', book_name: Book.first.name
      end.to change { Book.count }.by(-1)
    end
  end

  describe '#say' do
    it 'prints some text' do
      expect(self).to receive(:output).with('-- Hello')
      say 'Hello'
    end

    it 'prints some text as sub item' do
      expect(self).to receive(:output).with('   -> Hello')
      say 'Hello', :subitem
    end
  end

  describe '#say_with_time' do
    it 'wraps a block within some text' do
      text = ''
      allow(self).to receive(:output) do |new_text|
        text += "#{new_text}\n"
      end
      say_with_time 'Hello' do
        sleep 0.1
        12
      end
      expect(text).to match(/-- Hello\n   -> [0-9]\.[0-9]+s\n   -> 12 rows\n/)
    end
  end

  describe '#add_constraint' do
    after { drop_constraint :Book, :code if Neo4j::Label.constraint?(:Book, :code) }

    it 'adds a constraint to a property' do
      expect do
        add_constraint :Book, :code
      end.to change { Neo4j::Label.constraint?(:Book, :code) }.from(false).to(true)
    end

    it 'fails when constraint is already defined' do
      expect { add_constraint :Book, :name }.to raise_error('Duplicate constraint for Book#name')
    end
  end

  describe '#add_index' do
    after { drop_index :Book, :pages if Neo4j::Label.index?(:Book, :pages) }
    it 'adds an index to a property' do
      expect do
        add_index :Book, :pages
      end.to change { Neo4j::Label.index?(:Book, :pages) }.from(false).to(true)
    end

    it 'fails when index is already defined' do
      expect do
        expect { add_index :Book, :author_name }.to raise_error('Duplicate index for Book#author_name')
      end.not_to change { Neo4j::Label.create(:Book).indexes[:property_keys].flatten.count }
    end
  end

  describe '#populate_id_property' do
    before do
      3.times do
        execute 'CREATE (c:`Cat`)'
        execute 'CREATE (d:`Dog`)'
      end

      stub_active_node_class('Cat') {}
      stub_active_node_class('Dog') do
        id_property :my_id, on: :generate_id

        def generate_id
          "id-#{rand}"
        end
      end
    end

    it 'populates uuid' do
      populate_id_property :Cat
      uuids = Cat.all.pluck(:uuid)
      expect(uuids.count).to eq(3)
      expect(uuids.all? { |u| u =~ /\A([a-z0-9]+\-?)+\Z/ }).to be_truthy
    end

    it 'populates custom ids' do
      populate_id_property :Dog
      uuids = Dog.all(:n).pluck('n.my_id')
      expect(uuids.all? { |u| u.start_with?('id-') }).to be_truthy
    end
  end

  describe '#drop_constraint' do
    it 'removes a constraint from a property' do
      expect do
        drop_constraint :Book, :name
      end.to change { Neo4j::Label.constraint?(:Book, :name) }.from(true).to(false)
      expect { Book.create! name: Book.first.name }.not_to raise_error
    end

    it 'fails when constraint is not defined' do
      expect { drop_constraint :Book, :missing }.to raise_error('No such constraint for Book#missing')
    end
  end

  describe '#drop_index' do
    it 'removes an index from a property' do
      expect do
        drop_index :Book, :author_name
      end.to change { Neo4j::Label.index?(:Book, :author_name) }.from(true).to(false)
    end

    it 'fails when index is not defined' do
      expect do
        expect { drop_index :Book, :missing }.to raise_error('No such index for Book#missing')
      end.not_to change { Neo4j::Label.create(:Book).indexes[:property_keys].flatten.count }
    end
  end
end
