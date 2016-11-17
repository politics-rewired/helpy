module API
  module V1
    class Topics < Grape::API

      before do
        authenticate!
        restrict_to_role %w(admin agent)
      end

      include API::V1::Defaults
      include Grape::Kaminari

      # throttle max: 200, per: 1.minute

      # PRIVATE TICKET ENDPOINTS
      resource :tickets, desc: "Create and Manage private discussions" do

        paginate per_page: 20

        # LIST BY STATUS
        desc "List all PRIVATE tickets by status", {
          entity: Entity::Topic,
          notes: "List all open tickets (private topics)"
        }
        params do
          requires :status, type: String, desc: "Status group (New, Open, Pending, etc.)"
        end
        get "status/:status", root: :topics do
          if current_user.is_restricted?
            topics = Forum.find(1).topics.where(
              current_status: permitted_params[:status]
            ).all.tagged_with(current_user.team_list)
          else
            topics = Forum.find(1).topics.where(
              current_status: permitted_params[:status]
            )
          end
          present paginate(topics), with: Entity::Topic
        end

        # LIST BY USER
        desc "List all PRIVATE tickets for a user", {
          entity: Entity::Topic,
          notes: "List all tickets (private topics) for a given user"
        }
        params do
          requires :user_id, type: Integer, desc: "ID of the user"
        end
        get "user/:user_id", root: :topics do
          if current_user.is_restricted?
            topics = Forum.find(1).topics.where(user_id: permitted_params[:user_id]).all.tagged_with(current_user.team_list)
          else
            topics = Forum.find(1).topics.where(user_id: permitted_params[:user_id]).all
          end
          present paginate(topics), with: Entity::Topic
        end

        # SHOW ONE TICKET AND ITS THREAD
        desc "Show a single ticket", {
          entity: Entity::Topic,
          notes: "Show one ticket (private topic)"
        }
        params do
          requires :id, type: Integer, desc: "Ticket ID"
        end
        get ":id", root: :topics do
          if current_user.is_restricted?
            topic = Topic.includes(:posts).where(id: permitted_params[:id]).tagged_with(current_user.team_list)
          else
            topic = Topic.includes(:posts).find(permitted_params[:id])
          end
          if topic.present?
            present topic, with: Entity::Topic, posts: true
          else
            error!('Unauthorized. Insufficient access priviledges.', 401)
          end
        end

        # CREATE A NEW PRIVATE TICKET
        desc "Create a new ticket"
        params do
          requires :name, type: String, desc: "The subject of the ticket"
          requires :body, type: String, desc: "The post body"
          optional :team_list, type: String, desc: "The group that this ticket is assigned to"
          optional :channel, type: String, desc: "The source channel the ticket was created from"
          requires :user_id, type: Integer, desc: "the User ID"
        end

        post "", root: :topics do
          ticket = Topic.create!(
            forum_id: 1,
            name: params[:name],
            user_id: params[:user_id],
            current_status: 'new',
            private: true,
            team_list: params[:team_list],
            channel: params[:channel]
          )
          ticket.posts.create!(
            body: params[:body],
            user_id: params[:user_id],
            kind: 'first'
          )
          present ticket, with: Entity::Topic, posts: true
        end

        # ASSIGN TICKET
        desc "Assign ticket to an agent"
        params do
          requires :id, type: Integer, desc: "The ticket ID to update"
          requires :assigned_user_id, type: Integer, desc: "The assigned agent for this ticket"
        end

        post "assign/:id", root: :topics do
          if current_user.is_restricted?
            ticket = Topic.where(id: permitted_params[:id]).all.tagged_with(current_user.team_list).first
          else
            ticket = Topic.where(id: permitted_params[:id]).first
          end
          if ticket.present?
            previous_assigned_id = ticket.assigned_user_id? ? ticket.assigned_user_id : params[:assigned_user_id]
            assigned_user = User.find(params[:assigned_user_id])
            ticket.assign(previous_assigned_id, assigned_user.id)
            present ticket, with: Entity::Topic, posts: true
          else
            error!('Unauthorized. Insufficient access priviledges.', 401)
          end
        end

        # CHANGE TICKET STATUS
        desc "Change the status of a ticket"
        params do
          requires :id, type: Integer, desc: "The ticket ID to update"
          requires :status, type: String, desc: "The status of the topic (New, Open, Pending, Resolved)"
        end

        post "update_status/:id", root: :topics do
          if current_user.is_restricted?
            ticket = Topic.where(id: permitted_params[:id]).all.tagged_with(current_user.team_list).first
          else
            ticket = Topic.where(id: permitted_params[:id]).first
          end
          if ticket.present?
            case params[:status]
            when 'closed'
              ticket.close(current_user.id)
            when 'reopen'
              ticket.reopen(current_user.id)
            when 'trash'
              ticket.trash(current_user.id)
            else
              ticket.current_status = params[:status]
              ticket.save
            end
            present ticket, with: Entity::Topic, posts: true
          else
            error!('Unauthorized. Insufficient access priviledges.', 401)
          end
        end

        # MOVE FORUMS, BETWEEN PRIVATE/PUBLIC
        desc "Move forums, set privacy"
        params do
          requires :id, type: Integer, desc: "The ticket ID to update"
          requires :forum_id, type: Integer, desc: "The forum this ticket is associated with"
        end

        post "update_forum/:id", root: :topics do
          if current_user.is_restricted?
            ticket = Topic.where(id: permitted_params[:id]).all.tagged_with(current_user.team_list).first
          else
            ticket = Topic.where(id: permitted_params[:id]).first
          end
          if ticket.present?
            is_private = (permitted_params[:forum_id] == 1) ? true : false
            ticket.private = is_private
            ticket.forum_id = params[:forum_id]
            ticket.save
            present ticket, with: Entity::Topic, posts: true
          else
            error!('Unauthorized. Insufficient access priviledges.', 401)
          end
        end


      end

      # PUBLIC TOPIC ENDPOINTS
      resource :topics, desc: "Create and manage public discussions" do

        # SHOW ONE TOPIC AND ITS THREAD
        desc "Show a single ticket", {
          entity: Entity::Topic,
          notes: "Show one community topic"
        }
        params do
          requires :id, type: Integer, desc: "Topic ID"
        end
        get ":id", root: :topics do
          topic = Topic.includes(:posts).find(permitted_params[:id])#
          present topic, with: Entity::Topic, posts: true
        end


        # CREATE A NEW PUBLIC TOPIC
        desc "Create a new public topic"
        params do
          requires :name, type: String, desc: "The subject of the ticket"
          requires :body, type: String, desc: "The post body"
          requires :user_id, type: Integer, desc: "the User ID"
          requires :forum_id, type: Integer, desc: "The forum to add the topic to"
        end

        post "", root: :topics do
          topic = Topic.create!(
            forum_id: permitted_params[:forum_id],
            name: permitted_params[:name],
            user_id: permitted_params[:user_id],
            private: false
          )
          topic.posts.create!(
            body: permitted_params[:body],
            user_id: permitted_params[:user_id],
            kind: 'first'
          )
          present topic, with: Entity::Topic, posts: true
        end

        # UPDATE SINGLE TOPIC (PRIVACY, STATUS, ASSIGNED, ETC)
        desc "Update the status, assigned user, etc of a community topic"
        params do
          requires :id, type: Integer, desc: "The topic ID to update"
          requires :forum_id, type: Integer, desc: "The forum this topic is associated with"
          optional :current_status, type: String, desc: "The status of the topic (New, Open, Pending, Resolved)"
          optional :private, type: Boolean, desc: "Whether or not the topic is marked private"
          optional :assigned_user_id, type: Integer, desc: "The assigned agent for this topic"
        end

        patch ":id", root: :topics do
          topic = Topic.where(id: permitted_params[:id]).first
          topic.update!(
            forum_id: permitted_params[:forum_id],
            current_status: permitted_params[:current_status],
            private: permitted_params[:private],
            assigned_user_id: permitted_params[:assigned_user_id]
          )
          present topic, with: Entity::Topic, posts: true
        end

        # VOTE FOR A TOPIC
        desc "Vote for a topic", {
          entity: Entity::Topic,
          notes: "Vote for a given topic"
        }
        params do
          requires :id, type: Integer, desc: "The ID of the topic to vote for"
          #requires :user_id, type: Integer
        end
        patch ':id/vote', root: :topics do
          topic = Topic.where(id: permitted_params[:id]).first
          topic.votes.create!(
            user_id: current_user #|| permitted_params[:user_id]
          )
          present topic, with: Entity::Topic
        end

      end

    end
  end
end
