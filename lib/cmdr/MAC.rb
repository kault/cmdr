# Copyright (C) 2014 Wesleyan University
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#   http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

module MAC
	class << self
		def addr
			return @mac_address if defined? @mac_address and @mac_address
			re = %r/[^:\-](?:[0-9A-F][0-9A-F][:\-]){5}[0-9A-F][0-9A-F][^:\-]/io
			cmds = '/sbin/ifconfig', '/bin/ifconfig', 'ifconfig', 'ipconfig /all'

			null = test(?e, '/dev/null') ? '/dev/null' : 'NUL'

			lines = nil
			cmds.each do |cmd|
				stdout = IO.popen("#{ cmd } 2> #{ null }"){|fd| fd.readlines} rescue next
				next unless stdout and stdout.size > 0
				lines = stdout and break
			end
			raise "all of #{ cmds.join ' ' } failed" unless lines

			candidates = lines.select{|line| line =~ re}
			raise 'no mac address candidates' unless candidates.first
			candidates.map!{|c| c[re].strip}

			maddr = candidates.first
			raise 'no mac address found' unless maddr

			maddr.strip!
			maddr.instance_eval{ @list = candidates; def list() @list end }

			#This is really, really bizarre. I have no fucking clue what's going on here,
			#but for some reason, despite being in every way I can tell a perfectly ordinary
			#string, maddr as is crashes the JSON library. WTF, right? Anyways, for some reason
			#recomposing a new string from the byte array makes a good string, so that's what we're doing
			maddr = maddr.bytes.to_a.collect{|byte| byte.chr}.join
			@mac_address = maddr
		end
	end
end
