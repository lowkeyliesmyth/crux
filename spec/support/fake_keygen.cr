require "../../src/crux"

# Test double for Crux::Git::KeyGen.
#
# Records generate calls and fabricates the private/public key files so the
# command's "does the key already exist?" logic behaves realistically, all
# without invoking ssh-keygen.
class FakeKeyGen < Crux::Git::KeyGen
  property? available : Bool = true
  property? should_fail : Bool = false
  getter generated = [] of {path: String, comment: String}

  def generate(path : String, comment : String) : Crux::Git::Result
    @generated << {path: path, comment: comment}
    return Crux::Git::Result.new(1, "", "ssh-keygen exploded") if @should_fail

    File.write(path, "FAKE PRIVATE KEY\n")
    File.write("#{path}.pub", "ssh-ed25519 AAAAFAKE #{comment}\n")
    Crux::Git::Result.new(0, "", "")
  end
end
