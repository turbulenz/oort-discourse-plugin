require "net/http"
require "uri"
require "json"

module Jobs
  class CheckRecentUsers < ::Jobs::Scheduled
    every 10.seconds

    def initialize
      @badge_names = [
          "Pathfinder",
          "Trailblazer",
          "Explorer",
          "Adventurer",
          "Wayfarer",
          "Pioneer",
          "Master",
          "Oortian"
        ]
      @userid_scan_key = 'userid_last_checked'
      if !$redis.get(@userid_scan_key)
        $redis.set(@userid_scan_key, "1")
      end
    end

    def execute(args)
      #Kernel.puts(Time.new.inspect + ": execute check_recent_users")
      begin
        # Who's been recently seen
        users = User.joins(:single_sign_on_record).where("COALESCE(last_seen_at, '2010-01-01') >= CURRENT_TIMESTAMP - ('10 SECONDS'::INTERVAL)").pluck(:username, :external_username)
        users.each { |u| check_user(u) }
        # Slowly scan through all users to keep them up-to-date
        last_userid = $redis.get(@userid_scan_key).to_i
        last_userid += 1
        if last_userid > User.maximum(:id)
          last_userid = 1
        end
        $redis.set(@userid_scan_key, last_userid.to_s)
        #Kernel.puts("Checking: #{last_userid}")
        user = User.joins(:single_sign_on_record).where(users: {id: last_userid}).pluck(:username, :external_username)
        if !user.empty?
          check_user(user[0])
        end

      rescue Exception => e
        puts e.message
        puts e.backtrace.inspect
      end
    end

    def check_user(u)
      # usernames and external_usernames can differ e.g. - replace by _
      username = u[0]
      external_username = u[1]
      backer_username = external_username
      ## Testing
      #backer_username = "MorrigansRaven"
      #backer_username = "smoore"

      Kernel.puts("Checking #{username} (#{external_username})")
      Logster.logger.info("[oort] checking: #{external_username}")

      # Find their backing tier from the Discovery Server
      #uri = URI.parse("http://office.turbulenz.com:8493/players/#{backer_username}/tier")
      uri = URI.parse("https://wcds1.turbulenz.com:8902/players/#{backer_username}/tier")
      Kernel.puts("getting uri: #{uri}")
      response = Net::HTTP.get_response(uri)
      if response.is_a?(Net::HTTPSuccess)
        data = JSON.parse(response.body)
        Kernel.puts(data.inspect)
        Kernel.puts(data["tier"])
        if data["tier"] > 0
          Kernel.puts("Tier = #{data['tier']}")
          setup_tier(username, data["tier"])
        else
          Kernel.puts("[oort] error getting tier for: #{backer_username}")
          Logster.logger.error("[oort] error getting tier for: #{backer_username}")
        end
      else
        Kernel.puts("error response code: #{response.code}")
        Logster.logger.error("[oort] error response code: #{response.code}")
      end
    end

    def setup_tier(username, tier)
      Kernel.puts("setup_tier")
      user = User.find_by_username_or_email(username)

      steam_badge = Badge.find_by(id: 111)
      oortonline_badge = Badge.find_by(id: 112)
      if tier >= 1000
        # It's a Steam backing level
        tier -= 1000
        BadgeGranter.grant(steam_badge, user)
      else
        BadgeGranter.grant(oortonline_badge, user)
      end

      # Make sure they have this badge
      badge_name = @badge_names[tier - 1]
      Kernel.puts("Badge = " + badge_name)
      badge = Badge.find_by(name: badge_name)
      if badge
        user_badge = BadgeGranter.grant(badge, user)
        if (Time.now - user_badge[:granted_at]) < 60
          if user.title.blank? or @badge_names.include?(user.title)
            # If its new, and they don't currently have a title or are upgrading, set it
            #Kernel.puts("Setting #{username} title to #{badge_name}")
            Logster.logger.info("[oort] Setting #{username} title to #{badge_name}")
            user.title = badge_name
            user.save!
          else
            #Kernel.puts("#{username} already has title: #{user.title}")
            Logster.logger.info("[oort] #{username} already has title: #{user.title}")
          end
        end
      end

      founders_group = Group.lookup_group("Founders")
      in_founders_group = GroupUser.where("group_id = ? AND user_id = ?", founders_group[:id], user[:id])
      if in_founders_group.empty?
        # Add user to the founders group
        #Kernel.puts("Adding #{username} to Founders Group")
        Logster.logger.info("[oort] Adding #{username} to Founders Group")
        founders_group.add(user)
      end

    end


  end
end
