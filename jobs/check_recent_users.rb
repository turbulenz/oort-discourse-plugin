require "net/http"
require "uri"

module Jobs
  class CheckRecentUsers < ::Jobs::Scheduled
    every 10.seconds

    def initialize
      @badge_names = [
                      'Pathfinder',
                      'Trailblazer',
                      'Explorer',
                      'Adventurer',
                      'Wayfarer',
                      'Pioneer',
                      'Master',
                      'Oortian'
                    ]
    end

    def execute(args)
      # Who's been recently seen
      users = User.where("COALESCE(last_seen_at, '2010-01-01') >= CURRENT_TIMESTAMP - ('10 SECONDS'::INTERVAL)").pluck(:username)
      users.each { |u| check_user(u) }
    end

    def check_user(username)
      backer_username = username
      ## Testing
      #backer_username = "MorrigansRaven"

      #Kernel.puts("Checking #{username}")
      Logster.logger.info("[oort] checking: #{username}")

      # See if they are a backer
      # curl --data "action=get_backing&username=vengelfe" http://office.turbulenz.com:8492/wordpress-git/wordpress/wp-admin/admin-ajax.php
      uri = URI.parse("http://oortonline.com/wp-admin/admin-ajax.php")

      response = Net::HTTP.post_form(uri, {"action" => "get_backing", "username" => backer_username})

      if response.code == "200"
        check_response(username, response.body)
      else
        Logster.logger.error("[oort] backer request failed: #{response.code}")
      end
    end

    def check_response(username, body)
      user = User.find_by_username_or_email(username)
      founders_group = Group.lookup_group("Founders")
      in_founders_group = GroupUser.where("group_id = ? AND user_id = ?", founders_group[:id], user[:id])

      match = /^product_level=(?<level>\d+)/.match(body)
      if match
        if match[:level]

          # Make sure they have this badge
          badge_name = @badge_names[match[:level].to_i - 1]
          badge = Badge.find_by(name: badge_name)
          user_badge = BadgeGranter.grant(badge, user)
          if (Time.now - user_badge[:granted_at]) < 60
            if user.title.blank?
              # If its new, and they don't currently have a title, set it
              #Kernel.puts("Setting #{username} title to #{badge_name}")
              Logster.logger.info("[oort] Setting #{username} title to #{badge_name}")
              user.title = badge_name
              user.save!
            else
              #Kernel.puts("#{username} already has title: #{user.title}")
              Logster.logger.info("[oort] #{username} already has title: #{user.title}")
            end
          end

          if in_founders_group.empty?
            # Add user to the founders group
            #Kernel.puts("Adding #{username} to Founders Group")
            Logster.logger.info("[oort] Adding #{username} to Founders Group")
            founders_group.add(user)
          end
        end
      else
          if !in_founders_group.empty?
            # Remove user from the founders group
            #Kernel.puts("Removing #{username} from Founders Group")
            Logster.logger.info("[oort] Removing #{username} from Founders Group")
            founders_group.remove(user)
          end
      end
    end

  end
end
