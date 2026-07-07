export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  graphql_public: {
    Tables: {
      [_ in never]: never
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      graphql: {
        Args: {
          extensions?: Json
          operationName?: string
          query?: string
          variables?: Json
        }
        Returns: Json
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
  public: {
    Tables: {
      app_settings: {
        Row: {
          created_at: string
          key: string
          updated_at: string
          value: Json
        }
        Insert: {
          created_at?: string
          key: string
          updated_at?: string
          value: Json
        }
        Update: {
          created_at?: string
          key?: string
          updated_at?: string
          value?: Json
        }
        Relationships: []
      }
      audit_log: {
        Row: {
          action: string
          actor_profile_id: string | null
          created_at: string
          id: string
          metadata: Json | null
          target_id: string | null
          target_table: string | null
          updated_at: string
        }
        Insert: {
          action: string
          actor_profile_id?: string | null
          created_at?: string
          id?: string
          metadata?: Json | null
          target_id?: string | null
          target_table?: string | null
          updated_at?: string
        }
        Update: {
          action?: string
          actor_profile_id?: string | null
          created_at?: string
          id?: string
          metadata?: Json | null
          target_id?: string | null
          target_table?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "audit_log_actor_profile_id_fkey"
            columns: ["actor_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      badges: {
        Row: {
          created_at: string
          description: string | null
          icon_url: string | null
          id: string
          name: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          description?: string | null
          icon_url?: string | null
          id?: string
          name: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          description?: string | null
          icon_url?: string | null
          id?: string
          name?: string
          updated_at?: string
        }
        Relationships: []
      }
      check_ins: {
        Row: {
          created_at: string
          family_id: string
          id: string
          initiated_by: string | null
          member_id: string
          mood: Database["public"]["Enums"]["mood_type"]
          shared_with_family: boolean
          text_response: string | null
          updated_at: string
          voice_note_url: string | null
        }
        Insert: {
          created_at?: string
          family_id: string
          id?: string
          initiated_by?: string | null
          member_id: string
          mood: Database["public"]["Enums"]["mood_type"]
          shared_with_family?: boolean
          text_response?: string | null
          updated_at?: string
          voice_note_url?: string | null
        }
        Update: {
          created_at?: string
          family_id?: string
          id?: string
          initiated_by?: string | null
          member_id?: string
          mood?: Database["public"]["Enums"]["mood_type"]
          shared_with_family?: boolean
          text_response?: string | null
          updated_at?: string
          voice_note_url?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "check_ins_family_id_fkey"
            columns: ["family_id"]
            isOneToOne: false
            referencedRelation: "families"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "check_ins_initiated_by_fkey"
            columns: ["initiated_by"]
            isOneToOne: false
            referencedRelation: "family_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "check_ins_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "family_members"
            referencedColumns: ["id"]
          },
        ]
      }
      child_badges: {
        Row: {
          badge_id: string
          child_id: string
          created_at: string
          earned_at: string
          id: string
          updated_at: string
        }
        Insert: {
          badge_id: string
          child_id: string
          created_at?: string
          earned_at?: string
          id?: string
          updated_at?: string
        }
        Update: {
          badge_id?: string
          child_id?: string
          created_at?: string
          earned_at?: string
          id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "child_badges_badge_id_fkey"
            columns: ["badge_id"]
            isOneToOne: false
            referencedRelation: "badges"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "child_badges_child_id_fkey"
            columns: ["child_id"]
            isOneToOne: false
            referencedRelation: "family_members"
            referencedColumns: ["id"]
          },
        ]
      }
      child_profiles: {
        Row: {
          condition_tags: string[] | null
          created_at: string
          dob: string | null
          language_level: Database["public"]["Enums"]["language_level"]
          member_id: string
          photo_url: string | null
          updated_at: string
        }
        Insert: {
          condition_tags?: string[] | null
          created_at?: string
          dob?: string | null
          language_level?: Database["public"]["Enums"]["language_level"]
          member_id: string
          photo_url?: string | null
          updated_at?: string
        }
        Update: {
          condition_tags?: string[] | null
          created_at?: string
          dob?: string | null
          language_level?: Database["public"]["Enums"]["language_level"]
          member_id?: string
          photo_url?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "child_profiles_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: true
            referencedRelation: "family_members"
            referencedColumns: ["id"]
          },
        ]
      }
      child_provider_invites: {
        Row: {
          child_member_id: string
          code: string
          contact: string
          created_at: string
          expires_at: string
          id: string
          invited_by: string | null
          provider_type: Database["public"]["Enums"]["provider_type"]
          updated_at: string
          used_at: string | null
        }
        Insert: {
          child_member_id: string
          code: string
          contact: string
          created_at?: string
          expires_at: string
          id?: string
          invited_by?: string | null
          provider_type: Database["public"]["Enums"]["provider_type"]
          updated_at?: string
          used_at?: string | null
        }
        Update: {
          child_member_id?: string
          code?: string
          contact?: string
          created_at?: string
          expires_at?: string
          id?: string
          invited_by?: string | null
          provider_type?: Database["public"]["Enums"]["provider_type"]
          updated_at?: string
          used_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "child_provider_invites_child_member_id_fkey"
            columns: ["child_member_id"]
            isOneToOne: false
            referencedRelation: "family_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "child_provider_invites_invited_by_fkey"
            columns: ["invited_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      child_providers: {
        Row: {
          access_scope: string[]
          child_member_id: string
          created_at: string
          id: string
          invited_by: string | null
          provider_profile_id: string | null
          provider_type: Database["public"]["Enums"]["provider_type"]
          status: Database["public"]["Enums"]["provider_status"]
          updated_at: string
        }
        Insert: {
          access_scope?: string[]
          child_member_id: string
          created_at?: string
          id?: string
          invited_by?: string | null
          provider_profile_id?: string | null
          provider_type: Database["public"]["Enums"]["provider_type"]
          status?: Database["public"]["Enums"]["provider_status"]
          updated_at?: string
        }
        Update: {
          access_scope?: string[]
          child_member_id?: string
          created_at?: string
          id?: string
          invited_by?: string | null
          provider_profile_id?: string | null
          provider_type?: Database["public"]["Enums"]["provider_type"]
          status?: Database["public"]["Enums"]["provider_status"]
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "child_providers_child_member_id_fkey"
            columns: ["child_member_id"]
            isOneToOne: false
            referencedRelation: "family_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "child_providers_invited_by_fkey"
            columns: ["invited_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "child_providers_provider_profile_id_fkey"
            columns: ["provider_profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      content_variants: {
        Row: {
          created_at: string
          field_key: string
          id: string
          level: Database["public"]["Enums"]["language_level"]
          screen_key: string
          text: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          field_key: string
          id?: string
          level: Database["public"]["Enums"]["language_level"]
          screen_key: string
          text: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          field_key?: string
          id?: string
          level?: Database["public"]["Enums"]["language_level"]
          screen_key?: string
          text?: string
          updated_at?: string
        }
        Relationships: []
      }
      coping_strategies: {
        Row: {
          animation_key: string | null
          created_at: string
          family_id: string | null
          icon_url: string | null
          id: string
          is_global: boolean
          mood: Database["public"]["Enums"]["mood_type"]
          title: string
          updated_at: string
        }
        Insert: {
          animation_key?: string | null
          created_at?: string
          family_id?: string | null
          icon_url?: string | null
          id?: string
          is_global?: boolean
          mood: Database["public"]["Enums"]["mood_type"]
          title: string
          updated_at?: string
        }
        Update: {
          animation_key?: string | null
          created_at?: string
          family_id?: string | null
          icon_url?: string | null
          id?: string
          is_global?: boolean
          mood?: Database["public"]["Enums"]["mood_type"]
          title?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "coping_strategies_family_id_fkey"
            columns: ["family_id"]
            isOneToOne: false
            referencedRelation: "families"
            referencedColumns: ["id"]
          },
        ]
      }
      custom_word_lists: {
        Row: {
          added_by: string | null
          child_id: string
          created_at: string
          family_id: string
          id: string
          phonetic_hint: string | null
          updated_at: string
          word: string
        }
        Insert: {
          added_by?: string | null
          child_id: string
          created_at?: string
          family_id: string
          id?: string
          phonetic_hint?: string | null
          updated_at?: string
          word: string
        }
        Update: {
          added_by?: string | null
          child_id?: string
          created_at?: string
          family_id?: string
          id?: string
          phonetic_hint?: string | null
          updated_at?: string
          word?: string
        }
        Relationships: [
          {
            foreignKeyName: "custom_word_lists_added_by_fkey"
            columns: ["added_by"]
            isOneToOne: false
            referencedRelation: "family_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "custom_word_lists_child_id_fkey"
            columns: ["child_id"]
            isOneToOne: false
            referencedRelation: "family_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "custom_word_lists_family_id_fkey"
            columns: ["family_id"]
            isOneToOne: false
            referencedRelation: "families"
            referencedColumns: ["id"]
          },
        ]
      }
      emergency_contacts: {
        Row: {
          created_at: string
          family_id: string
          id: string
          name: string
          phone: string
          relation: string | null
          updated_at: string
        }
        Insert: {
          created_at?: string
          family_id: string
          id?: string
          name: string
          phone: string
          relation?: string | null
          updated_at?: string
        }
        Update: {
          created_at?: string
          family_id?: string
          id?: string
          name?: string
          phone?: string
          relation?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "emergency_contacts_family_id_fkey"
            columns: ["family_id"]
            isOneToOne: false
            referencedRelation: "families"
            referencedColumns: ["id"]
          },
        ]
      }
      families: {
        Row: {
          created_at: string
          created_by: string | null
          id: string
          language_default: string | null
          name: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          id?: string
          language_default?: string | null
          name: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          created_by?: string | null
          id?: string
          language_default?: string | null
          name?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "families_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      family_invites: {
        Row: {
          code: string
          contact: string | null
          created_at: string
          expires_at: string
          family_id: string
          id: string
          role: Database["public"]["Enums"]["family_role"]
          updated_at: string
          used_at: string | null
        }
        Insert: {
          code: string
          contact?: string | null
          created_at?: string
          expires_at: string
          family_id: string
          id?: string
          role: Database["public"]["Enums"]["family_role"]
          updated_at?: string
          used_at?: string | null
        }
        Update: {
          code?: string
          contact?: string | null
          created_at?: string
          expires_at?: string
          family_id?: string
          id?: string
          role?: Database["public"]["Enums"]["family_role"]
          updated_at?: string
          used_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "family_invites_family_id_fkey"
            columns: ["family_id"]
            isOneToOne: false
            referencedRelation: "families"
            referencedColumns: ["id"]
          },
        ]
      }
      family_members: {
        Row: {
          created_at: string
          family_id: string
          id: string
          joined_at: string
          profile_id: string | null
          role: Database["public"]["Enums"]["family_role"]
          status: Database["public"]["Enums"]["member_status"]
          status_label: string | null
          updated_at: string
        }
        Insert: {
          created_at?: string
          family_id: string
          id?: string
          joined_at?: string
          profile_id?: string | null
          role: Database["public"]["Enums"]["family_role"]
          status?: Database["public"]["Enums"]["member_status"]
          status_label?: string | null
          updated_at?: string
        }
        Update: {
          created_at?: string
          family_id?: string
          id?: string
          joined_at?: string
          profile_id?: string | null
          role?: Database["public"]["Enums"]["family_role"]
          status?: Database["public"]["Enums"]["member_status"]
          status_label?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "family_members_family_id_fkey"
            columns: ["family_id"]
            isOneToOne: false
            referencedRelation: "families"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "family_members_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      habit_logs: {
        Row: {
          completed: boolean
          created_at: string
          date: string
          habit_id: string
          id: string
          updated_at: string
        }
        Insert: {
          completed?: boolean
          created_at?: string
          date: string
          habit_id: string
          id?: string
          updated_at?: string
        }
        Update: {
          completed?: boolean
          created_at?: string
          date?: string
          habit_id?: string
          id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "habit_logs_habit_id_fkey"
            columns: ["habit_id"]
            isOneToOne: false
            referencedRelation: "habits"
            referencedColumns: ["id"]
          },
        ]
      }
      habits: {
        Row: {
          child_id: string
          created_at: string
          family_id: string
          id: string
          name: string
          target_frequency: number
          updated_at: string
        }
        Insert: {
          child_id: string
          created_at?: string
          family_id: string
          id?: string
          name: string
          target_frequency?: number
          updated_at?: string
        }
        Update: {
          child_id?: string
          created_at?: string
          family_id?: string
          id?: string
          name?: string
          target_frequency?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "habits_child_id_fkey"
            columns: ["child_id"]
            isOneToOne: false
            referencedRelation: "family_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "habits_family_id_fkey"
            columns: ["family_id"]
            isOneToOne: false
            referencedRelation: "families"
            referencedColumns: ["id"]
          },
        ]
      }
      location_sharing_prefs: {
        Row: {
          active_hours: Json | null
          created_at: string
          member_id: string
          updated_at: string
          visibility: Database["public"]["Enums"]["location_visibility"]
        }
        Insert: {
          active_hours?: Json | null
          created_at?: string
          member_id: string
          updated_at?: string
          visibility?: Database["public"]["Enums"]["location_visibility"]
        }
        Update: {
          active_hours?: Json | null
          created_at?: string
          member_id?: string
          updated_at?: string
          visibility?: Database["public"]["Enums"]["location_visibility"]
        }
        Relationships: [
          {
            foreignKeyName: "location_sharing_prefs_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: true
            referencedRelation: "family_members"
            referencedColumns: ["id"]
          },
        ]
      }
      member_locations: {
        Row: {
          created_at: string
          id: string
          lat: number
          lng: number
          member_id: string
          recorded_at: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          id?: string
          lat: number
          lng: number
          member_id: string
          recorded_at?: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          id?: string
          lat?: number
          lng?: number
          member_id?: string
          recorded_at?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "member_locations_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "family_members"
            referencedColumns: ["id"]
          },
        ]
      }
      nudges: {
        Row: {
          created_at: string
          family_id: string
          from_member: string
          id: string
          message: string | null
          read_at: string | null
          to_member: string
          trigger_reason: string | null
          updated_at: string
          variant: Database["public"]["Enums"]["nudge_variant"]
        }
        Insert: {
          created_at?: string
          family_id: string
          from_member: string
          id?: string
          message?: string | null
          read_at?: string | null
          to_member: string
          trigger_reason?: string | null
          updated_at?: string
          variant: Database["public"]["Enums"]["nudge_variant"]
        }
        Update: {
          created_at?: string
          family_id?: string
          from_member?: string
          id?: string
          message?: string | null
          read_at?: string | null
          to_member?: string
          trigger_reason?: string | null
          updated_at?: string
          variant?: Database["public"]["Enums"]["nudge_variant"]
        }
        Relationships: [
          {
            foreignKeyName: "nudges_family_id_fkey"
            columns: ["family_id"]
            isOneToOne: false
            referencedRelation: "families"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "nudges_from_member_fkey"
            columns: ["from_member"]
            isOneToOne: false
            referencedRelation: "family_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "nudges_to_member_fkey"
            columns: ["to_member"]
            isOneToOne: false
            referencedRelation: "family_members"
            referencedColumns: ["id"]
          },
        ]
      }
      points_ledger: {
        Row: {
          child_id: string
          created_at: string
          delta: number
          id: string
          reason: string | null
          updated_at: string
        }
        Insert: {
          child_id: string
          created_at?: string
          delta: number
          id?: string
          reason?: string | null
          updated_at?: string
        }
        Update: {
          child_id?: string
          created_at?: string
          delta?: number
          id?: string
          reason?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "points_ledger_child_id_fkey"
            columns: ["child_id"]
            isOneToOne: false
            referencedRelation: "family_members"
            referencedColumns: ["id"]
          },
        ]
      }
      profiles: {
        Row: {
          avatar_url: string | null
          created_at: string
          full_name: string | null
          id: string
          role_global: Database["public"]["Enums"]["role_global_type"]
          updated_at: string
        }
        Insert: {
          avatar_url?: string | null
          created_at?: string
          full_name?: string | null
          id: string
          role_global?: Database["public"]["Enums"]["role_global_type"]
          updated_at?: string
        }
        Update: {
          avatar_url?: string | null
          created_at?: string
          full_name?: string | null
          id?: string
          role_global?: Database["public"]["Enums"]["role_global_type"]
          updated_at?: string
        }
        Relationships: []
      }
      push_campaigns: {
        Row: {
          body: string | null
          created_at: string
          id: string
          scheduled_at: string | null
          sent_at: string | null
          target_audience: string | null
          title: string
          updated_at: string
        }
        Insert: {
          body?: string | null
          created_at?: string
          id?: string
          scheduled_at?: string | null
          sent_at?: string | null
          target_audience?: string | null
          title: string
          updated_at?: string
        }
        Update: {
          body?: string | null
          created_at?: string
          id?: string
          scheduled_at?: string | null
          sent_at?: string | null
          target_audience?: string | null
          title?: string
          updated_at?: string
        }
        Relationships: []
      }
      reward_redemptions: {
        Row: {
          approved_by: string | null
          child_id: string
          created_at: string
          id: string
          item_id: string
          status: Database["public"]["Enums"]["redemption_status"]
          updated_at: string
        }
        Insert: {
          approved_by?: string | null
          child_id: string
          created_at?: string
          id?: string
          item_id: string
          status?: Database["public"]["Enums"]["redemption_status"]
          updated_at?: string
        }
        Update: {
          approved_by?: string | null
          child_id?: string
          created_at?: string
          id?: string
          item_id?: string
          status?: Database["public"]["Enums"]["redemption_status"]
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "reward_redemptions_approved_by_fkey"
            columns: ["approved_by"]
            isOneToOne: false
            referencedRelation: "family_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "reward_redemptions_child_id_fkey"
            columns: ["child_id"]
            isOneToOne: false
            referencedRelation: "family_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "reward_redemptions_item_id_fkey"
            columns: ["item_id"]
            isOneToOne: false
            referencedRelation: "reward_shop_items"
            referencedColumns: ["id"]
          },
        ]
      }
      reward_shop_items: {
        Row: {
          cost_points: number
          created_at: string
          family_id: string | null
          icon_url: string | null
          id: string
          name: string
          updated_at: string
        }
        Insert: {
          cost_points: number
          created_at?: string
          family_id?: string | null
          icon_url?: string | null
          id?: string
          name: string
          updated_at?: string
        }
        Update: {
          cost_points?: number
          created_at?: string
          family_id?: string | null
          icon_url?: string | null
          id?: string
          name?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "reward_shop_items_family_id_fkey"
            columns: ["family_id"]
            isOneToOne: false
            referencedRelation: "families"
            referencedColumns: ["id"]
          },
        ]
      }
      routine_completions: {
        Row: {
          child_id: string
          created_at: string
          date: string
          id: string
          routine_id: string
          steps_done: Json
          updated_at: string
        }
        Insert: {
          child_id: string
          created_at?: string
          date: string
          id?: string
          routine_id: string
          steps_done?: Json
          updated_at?: string
        }
        Update: {
          child_id?: string
          created_at?: string
          date?: string
          id?: string
          routine_id?: string
          steps_done?: Json
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "routine_completions_child_id_fkey"
            columns: ["child_id"]
            isOneToOne: false
            referencedRelation: "family_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "routine_completions_routine_id_fkey"
            columns: ["routine_id"]
            isOneToOne: false
            referencedRelation: "routines"
            referencedColumns: ["id"]
          },
        ]
      }
      routine_steps: {
        Row: {
          created_at: string
          icon: string | null
          id: string
          name: string
          order_index: number
          routine_id: string
          time_allocation_minutes: number | null
          updated_at: string
        }
        Insert: {
          created_at?: string
          icon?: string | null
          id?: string
          name: string
          order_index?: number
          routine_id: string
          time_allocation_minutes?: number | null
          updated_at?: string
        }
        Update: {
          created_at?: string
          icon?: string | null
          id?: string
          name?: string
          order_index?: number
          routine_id?: string
          time_allocation_minutes?: number | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "routine_steps_routine_id_fkey"
            columns: ["routine_id"]
            isOneToOne: false
            referencedRelation: "routines"
            referencedColumns: ["id"]
          },
        ]
      }
      routines: {
        Row: {
          child_id: string
          created_at: string
          family_id: string
          id: string
          name: string
          updated_at: string
        }
        Insert: {
          child_id: string
          created_at?: string
          family_id: string
          id?: string
          name: string
          updated_at?: string
        }
        Update: {
          child_id?: string
          created_at?: string
          family_id?: string
          id?: string
          name?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "routines_child_id_fkey"
            columns: ["child_id"]
            isOneToOne: false
            referencedRelation: "family_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "routines_family_id_fkey"
            columns: ["family_id"]
            isOneToOne: false
            referencedRelation: "families"
            referencedColumns: ["id"]
          },
        ]
      }
      sos_alerts: {
        Row: {
          created_at: string
          family_id: string
          id: string
          lat: number | null
          lng: number | null
          resolved_at: string | null
          resolved_by: string | null
          status: Database["public"]["Enums"]["sos_status"]
          triggered_by: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          family_id: string
          id?: string
          lat?: number | null
          lng?: number | null
          resolved_at?: string | null
          resolved_by?: string | null
          status?: Database["public"]["Enums"]["sos_status"]
          triggered_by: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          family_id?: string
          id?: string
          lat?: number | null
          lng?: number | null
          resolved_at?: string | null
          resolved_by?: string | null
          status?: Database["public"]["Enums"]["sos_status"]
          triggered_by?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "sos_alerts_family_id_fkey"
            columns: ["family_id"]
            isOneToOne: false
            referencedRelation: "families"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sos_alerts_resolved_by_fkey"
            columns: ["resolved_by"]
            isOneToOne: false
            referencedRelation: "family_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "sos_alerts_triggered_by_fkey"
            columns: ["triggered_by"]
            isOneToOne: false
            referencedRelation: "family_members"
            referencedColumns: ["id"]
          },
        ]
      }
      sos_cooldowns: {
        Row: {
          created_at: string
          last_triggered_at: string
          member_id: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          last_triggered_at?: string
          member_id: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          last_triggered_at?: string
          member_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "sos_cooldowns_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: true
            referencedRelation: "family_members"
            referencedColumns: ["id"]
          },
        ]
      }
      speech_attempts: {
        Row: {
          ai_feedback: string | null
          ai_score: number | null
          alternatives: Json | null
          attempt_number: number
          child_id: string
          confidence: number | null
          created_at: string
          custom_word_id: string | null
          exercise_id: string | null
          id: string
          transcript: string | null
          updated_at: string
        }
        Insert: {
          ai_feedback?: string | null
          ai_score?: number | null
          alternatives?: Json | null
          attempt_number?: number
          child_id: string
          confidence?: number | null
          created_at?: string
          custom_word_id?: string | null
          exercise_id?: string | null
          id?: string
          transcript?: string | null
          updated_at?: string
        }
        Update: {
          ai_feedback?: string | null
          ai_score?: number | null
          alternatives?: Json | null
          attempt_number?: number
          child_id?: string
          confidence?: number | null
          created_at?: string
          custom_word_id?: string | null
          exercise_id?: string | null
          id?: string
          transcript?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "speech_attempts_child_id_fkey"
            columns: ["child_id"]
            isOneToOne: false
            referencedRelation: "family_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "speech_attempts_custom_word_id_fkey"
            columns: ["custom_word_id"]
            isOneToOne: false
            referencedRelation: "custom_word_lists"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "speech_attempts_exercise_id_fkey"
            columns: ["exercise_id"]
            isOneToOne: false
            referencedRelation: "speech_exercises"
            referencedColumns: ["id"]
          },
        ]
      }
      speech_exercises: {
        Row: {
          audio_url: string | null
          category: string | null
          created_at: string
          difficulty: Database["public"]["Enums"]["speech_difficulty"]
          id: string
          image_url: string | null
          phonetic_hint: string | null
          target_word: string
          updated_at: string
        }
        Insert: {
          audio_url?: string | null
          category?: string | null
          created_at?: string
          difficulty?: Database["public"]["Enums"]["speech_difficulty"]
          id?: string
          image_url?: string | null
          phonetic_hint?: string | null
          target_word: string
          updated_at?: string
        }
        Update: {
          audio_url?: string | null
          category?: string | null
          created_at?: string
          difficulty?: Database["public"]["Enums"]["speech_difficulty"]
          id?: string
          image_url?: string | null
          phonetic_hint?: string | null
          target_word?: string
          updated_at?: string
        }
        Relationships: []
      }
      task_categories: {
        Row: {
          color: string
          created_at: string
          family_id: string | null
          id: string
          name: string
          updated_at: string
        }
        Insert: {
          color: string
          created_at?: string
          family_id?: string | null
          id?: string
          name: string
          updated_at?: string
        }
        Update: {
          color?: string
          created_at?: string
          family_id?: string | null
          id?: string
          name?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "task_categories_family_id_fkey"
            columns: ["family_id"]
            isOneToOne: false
            referencedRelation: "families"
            referencedColumns: ["id"]
          },
        ]
      }
      task_verifications: {
        Row: {
          created_at: string
          id: string
          notes: string | null
          photo_url: string | null
          task_id: string
          updated_at: string
          verified_at: string
          verified_by: string | null
        }
        Insert: {
          created_at?: string
          id?: string
          notes?: string | null
          photo_url?: string | null
          task_id: string
          updated_at?: string
          verified_at?: string
          verified_by?: string | null
        }
        Update: {
          created_at?: string
          id?: string
          notes?: string | null
          photo_url?: string | null
          task_id?: string
          updated_at?: string
          verified_at?: string
          verified_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "task_verifications_task_id_fkey"
            columns: ["task_id"]
            isOneToOne: false
            referencedRelation: "tasks"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "task_verifications_verified_by_fkey"
            columns: ["verified_by"]
            isOneToOne: false
            referencedRelation: "family_members"
            referencedColumns: ["id"]
          },
        ]
      }
      tasks: {
        Row: {
          assignee_id: string | null
          category_id: string | null
          created_at: string
          created_by: string | null
          date: string
          family_id: string
          google_event_id: string | null
          id: string
          priority: Database["public"]["Enums"]["task_priority"]
          reminder_at: string | null
          requires_verification: boolean
          status: Database["public"]["Enums"]["task_status"]
          time: string | null
          title: string
          updated_at: string
          verification_type: Database["public"]["Enums"]["verification_type"]
        }
        Insert: {
          assignee_id?: string | null
          category_id?: string | null
          created_at?: string
          created_by?: string | null
          date: string
          family_id: string
          google_event_id?: string | null
          id?: string
          priority?: Database["public"]["Enums"]["task_priority"]
          reminder_at?: string | null
          requires_verification?: boolean
          status?: Database["public"]["Enums"]["task_status"]
          time?: string | null
          title: string
          updated_at?: string
          verification_type?: Database["public"]["Enums"]["verification_type"]
        }
        Update: {
          assignee_id?: string | null
          category_id?: string | null
          created_at?: string
          created_by?: string | null
          date?: string
          family_id?: string
          google_event_id?: string | null
          id?: string
          priority?: Database["public"]["Enums"]["task_priority"]
          reminder_at?: string | null
          requires_verification?: boolean
          status?: Database["public"]["Enums"]["task_status"]
          time?: string | null
          title?: string
          updated_at?: string
          verification_type?: Database["public"]["Enums"]["verification_type"]
        }
        Relationships: [
          {
            foreignKeyName: "tasks_assignee_id_fkey"
            columns: ["assignee_id"]
            isOneToOne: false
            referencedRelation: "family_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tasks_category_id_fkey"
            columns: ["category_id"]
            isOneToOne: false
            referencedRelation: "task_categories"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tasks_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "family_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tasks_family_id_fkey"
            columns: ["family_id"]
            isOneToOne: false
            referencedRelation: "families"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      has_provider_access: {
        Args: { p_child_member_id: string; p_scope: string }
        Returns: boolean
      }
      is_family_member: { Args: { p_family_id: string }; Returns: boolean }
      is_platform_admin: { Args: never; Returns: boolean }
      member_family_id: { Args: { p_member_id: string }; Returns: string }
      my_member_id: { Args: { p_family_id: string }; Returns: string }
      uuid_generate_v7: { Args: never; Returns: string }
    }
    Enums: {
      family_role: "family_admin" | "family_member" | "child"
      language_level: "simple" | "standard" | "full"
      location_visibility: "all" | "parents_only" | "none"
      member_status: "active" | "invited" | "removed"
      mood_type: "angry" | "overwhelmed" | "calm" | "happy"
      nudge_variant: "concern" | "encouragement" | "task_reminder"
      provider_status: "invited" | "active" | "removed"
      provider_type: "doctor" | "therapist" | "teacher" | "other"
      redemption_status: "pending" | "approved" | "denied"
      role_global_type: "user" | "platform_admin"
      sos_status: "active" | "resolved"
      speech_difficulty: "easy" | "medium" | "hard"
      task_priority: "low" | "medium" | "high"
      task_status: "pending" | "completed" | "awaiting_verification" | "overdue"
      verification_type: "photo" | "adult_approval" | "none"
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  graphql_public: {
    Enums: {},
  },
  public: {
    Enums: {
      family_role: ["family_admin", "family_member", "child"],
      language_level: ["simple", "standard", "full"],
      location_visibility: ["all", "parents_only", "none"],
      member_status: ["active", "invited", "removed"],
      mood_type: ["angry", "overwhelmed", "calm", "happy"],
      nudge_variant: ["concern", "encouragement", "task_reminder"],
      provider_status: ["invited", "active", "removed"],
      provider_type: ["doctor", "therapist", "teacher", "other"],
      redemption_status: ["pending", "approved", "denied"],
      role_global_type: ["user", "platform_admin"],
      sos_status: ["active", "resolved"],
      speech_difficulty: ["easy", "medium", "hard"],
      task_priority: ["low", "medium", "high"],
      task_status: ["pending", "completed", "awaiting_verification", "overdue"],
      verification_type: ["photo", "adult_approval", "none"],
    },
  },
} as const

