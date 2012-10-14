require "spec_helper"

describe Lobot::CLI do
  let(:lobot_config) { Lobot::Config.new }
  let(:cli) { subject }

  before do
    cli.stub(:lobot_config).and_return(lobot_config)
  end

  describe "#ssh" do
    it "starts an ssh session to the lobot host" do
      cli.should_receive(:exec).with("ssh -i #{cli.lobot_config.server_ssh_key} ubuntu@#{cli.lobot_config.master} -p #{cli.lobot_config.ssh_port}")
      cli.ssh
    end
  end

  describe "#open" do
    let(:lobot_config) { Lobot::Config.new(basic_auth_user: "ci", basic_auth_password: "secret") }

    it "opens a web browser with the lobot page" do
      cli.should_receive(:exec).with("open https://#{cli.lobot_config.basic_auth_user}:#{cli.lobot_config.basic_auth_password}@#{cli.lobot_config.master}/")
      cli.open
    end
  end

  describe "#create_vagrant" do
    let(:tempfile) do
      t = Tempfile.new('lobot-config')
      t.write YAML.dump(basic_auth_user: "ci", basic_auth_password: "secret")
      t.close
      t
    end

    def lobot_config
      Lobot::Config.from_file(tempfile.path)
    end

    it "starts a virtual machine" do
      cli.create_vagrant
      Lobot::PortChecker.is_listening?('192.168.33.10', 22, 1).should be
    end

    it "updates the config master ip address" do
      expect { cli.create_vagrant }.to change { lobot_config.master }.to('192.168.33.10')
    end
  end

  describe "#bootstrap", slow: true do
    before { cli.create_vagrant }

    it "installs all necessary packages" do
      cli.bootstrap

      Net::SSH.start(cli.master_server.ip, "ubuntu", keys: [cli.master_server.key], timeout: 10000) do |ssh|
        ssh.exec!("dpkg --get-selections").should include("libncurses5-dev")
      end
    end

    it "installs rvm" do
      cli.bootstrap

      Net::SSH.start(cli.master_server.ip, "ubuntu", keys: [cli.master_server.key], timeout: 10000) do |ssh|
        ssh.exec!("ls /usr/local/rvm/").should_not be_empty
      end
    end

    it "adds the ubuntu user to the rvm group" do
      cli.bootstrap
      Net::SSH.start(cli.master_server.ip, "ubuntu", keys: [cli.master_server.key], timeout: 10000) do |ssh|
        ssh.exec!("groups ubuntu").should include("rvm")
      end
    end
  end

  describe "#chef" do
    before do
      cli.create_vagrant
      cli.bootstrap
    end

    it "runs chef" do
      cli.lobot_config.recipes = ["pivotal_ci::nginx"]
      cli.chef
      Net::SSH.start(cli.master_server.ip, "ubuntu", keys: [cli.master_server.key], timeout: 10000) do |ssh|
        ssh.exec!("ls /etc/nginx").should_not be_empty
      end
    end
  end
end