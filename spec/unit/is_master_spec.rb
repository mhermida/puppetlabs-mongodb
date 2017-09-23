require 'spec_helper'

describe Facter::Util::Fact do

  before { Facter.clear }
  after  { Facter.clear }

  describe 'is_master', type: :fact do

    context 'MongoDB 3.4.x replset and master node' do

      let(:mongoPort) { 27017 }

      before do
        Facter::Util::Resolution.stubs(:which).with('mongo').returns(true)
        Facter::Util::Resolution.stubs(:which).with('mongod').returns(true)
        Facter::Core::Execution.stubs(:execute).with("mongo --quiet --port #{mongoPort} --eval \"printjson(db.adminCommand({ ping: 1 }))\"").returns( '{ "ok" : 1 }' )
        Facter::Core::Execution.stubs(:execute).with("mongo --quiet --port #{mongoPort} --eval \"printjson(db.isMaster().ismaster)\"").returns(true)
      end
      it 'returns true' do
        allow(YAML).to receive(:load_file)
          .and_return({'net.port' => mongoPort})

        expect(Facter.fact(:is_master).value).to be(true)
      end

    end
  end
end
