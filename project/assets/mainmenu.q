script #"0xfeb64820"
    dialog_box_exit
    if ScreenElementExists Id = current_menu_anchor
        DestroyScreenElement Id = current_menu_anchor
    endif
    if ScreenElementExists Id = #"0xbd9e3775"
        DestroyScreenElement Id = #"0xbd9e3775"
    endif
    if ScreenElementExists Id = choose_trick_menu_container
        DestroyScreenElement Id = choose_trick_menu_container
    endif
    if GotParam show_recomp_quit_confirmation
        create_error_box {
            Title = "QUIT?"
            text = "Are you sure?"
            Pos = (310.0, 240.0)
            just = [ center center ]
            text_rgba = [ 88 105 112 128 ]
            text_dims = (200.0, 0.0)
            pad_back_script = #"0xfeb64820"
            buttons = [
                {
                    font = text_a1
                    text = "QUIT"
                    pad_choose_script = #"0x83e7df93"
                }
                {
                    font = text_a1
                    text = "CANCEL"
                    pad_choose_script = #"0xfeb64820"
                }
            ]
        }
        return
    endif
    Change sysnotify_allow_invite = 1
    EnableUserMusic
    #"0x650d2c8e"
    if ($pause_fmv_playing = 0)
        #"0x9125a704"
    else
        #"0x28122337" TextureSlot = 0 Frame = 1 loop_start = 110 loop_end = 218
    endif
    Change ui_x360_sign_in_checked = 0
    #"0x53c6cdcf" {
        menu_id = #"0x105a3241"
        #"0xc868adf4" = #"0xef88ddda"
        pad_back_script = NullScript
        #"0x5df73865" = NullScript
        dont_allow_wrap
    }
    #"0xe694a1c9" {
        text = "CAREER"
        pad_choose_script = #"0x8875eaf7"
        pad_choose_params = {
            #"0xf1ff8b68" = #"0x27c830a8"
            career
        }
        #"0x2660cd26" = #"0x6d4328c8"
    }
    #"0xe694a1c9" {
        Id = #"0xbf9c6f1b"
        text = "2 PLAYER"
        pad_choose_script = #"0xea8b6fb3"
        #"0x2660cd26" = #"0x185d4e35"
    }
    #"0xe694a1c9" {
        text = "FREE SKATE"
        pad_choose_script = #"0x8875eaf7"
        pad_choose_params = {
            #"0xf1ff8b68" = #"0x16178cc7"
        }
    }
    #"0xe694a1c9" {
        text = "CREATE"
        pad_choose_script = #"0x8875eaf7"
        pad_choose_params = {
            #"0xf1ff8b68" = #"0x577e1f34"
            Create
        }
    }
    #"0xe694a1c9" {
        text = "PRO TRICKS"
        pad_choose_script = #"0x8875eaf7"
        pad_choose_params = {
            #"0xf1ff8b68" = #"0x9fdfffb0"
        }
        #"0x2660cd26" = #"0x73708d79"
    }
    #"0xe694a1c9" {
        text = "OPTIONS"
        pad_choose_script = #"0x8875eaf7"
        pad_choose_params = {
            #"0xf1ff8b68" = #"0xc8aaba53"
        }
        #"0x2660cd26" = #"0xb0091dbe"
    }
    #"0xe694a1c9" {
        text = "QUIT"
        pad_choose_script = #"0xfeb64820"
        pad_choose_params = {
            show_recomp_quit_confirmation
        }
    }
    #"0x0ea348de" #"0x604efa33" = generic_helper_text_left_right_no_back
endscript
