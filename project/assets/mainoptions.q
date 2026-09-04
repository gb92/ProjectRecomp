script #"0xa70d9a1d"
    #"0xe0ae72e8" {
        Title = "OPTIONS"
        #"0xcdc3f6a0" = #"0x3acac82a"
    }
    <#"0xc1c3dbbc"> = 0
    if IsPS3
        <#"0xc1c3dbbc"> = 1
    endif
    if IsXenon
        if CheckForSignIn local
            <#"0xc1c3dbbc"> = 1
        endif
    endif
    if (<#"0xc1c3dbbc"> = 1)
        #"0x59486bf2" {
            text = "SAVE GAME"
            #"0xf1ff8b68" = #"0x88856173"
        }
        #"0x59486bf2" {
            text = "LOAD GAME"
            #"0xf1ff8b68" = #"0x5e92223a"
        }
    else
        #"0x59486bf2" {
            text = "SAVE GAME"
            not_focusable
        }
        #"0x59486bf2" {
            text = "LOAD GAME"
            not_focusable
        }
    endif
    #"0x59486bf2" {
        text = "GAME SETTINGS"
        #"0xf1ff8b68" = #"0x117e1a1d"
    }
    if GetGlobalFlag flag = $CAREER_STARTED
        #"0x59486bf2" {
            text = "GAME PROGRESS"
            #"0xf1ff8b68" = #"0x71a59446"
        }
    else
        #"0x59486bf2" {
            text = "GAME PROGRESS"
            not_focusable
        }
    endif
    #"0x59486bf2" {
        text = "HIGH SCORES"
        #"0xf1ff8b68" = #"0x203de4af"
    }
    #"0x59486bf2" {
        text = "CHEAT CODES"
        pad_choose_script = #"0xa00d5146"
    }
    #"0x59486bf2" {
        text = "GAME MOVIES"
        #"0xf1ff8b68" = #"0xe1733ec1"
    }
    #"0x59486bf2" {
        text = "GRAPHICS"
        pad_choose_script = #"0xa9ba1467"
    }
    #"0x59486bf2" {
        text = "DONE"
        #"0xf1ff8b68" = #"0x3acac82a"
    }
    #"0x49a03394"
endscript
