# -*- mode: sh; sh-indentation: 4; indent-tabs-mode: nil; sh-basic-offset: 4; -*-
# Copyright (c) 2016-2020 Sebastian Gniazdowski and contributors

builtin source "${ZINIT[BIN_DIR]}/zinit-side.zsh"

# FUNCTION: .zinit-parse-json [[[
# Retrievies the ice-list from given profile from
# the JSON of the package.json.
.zinit-parse-json() {
    emulate -LR zsh
    setopt extendedglob warncreateglobal typesetsilent

    local -A __pos_to_level __level_to_pos __pair_map \
        __final_pairs __Strings __Counts
    local __input=$1 __workbuf=$1 __key=$2 __varname=$3 \
        __style __quoting
    integer __nest=${4:-1} __idx=0 __pair_idx __level=0 \
        __start __end __sidx=1 __had_quoted_value=0
    local -a match mbegin mend __pair_order

    (( ${(P)+__varname} )) || typeset -gA "$__varname"

    __pair_map=( "{" "}" "[" "]" )
    while [[ $__workbuf = (#b)[^"{}[]\\\"'":,]#((["{[]}\"'":,])|[\\](*))(*) ]]; do
        [[ -n ${match[3]} ]] && {
            __idx+=${mbegin[1]}

            [[ $__quoting = \' ]] && \
                { __workbuf=${match[3]}; } || \
                { __workbuf=${match[3]:1}; (( ++ __idx )); }

        } || {
            __idx+=${mbegin[1]}
            [[ -z $__quoting ]] && {
                if [[ ${match[1]} = ["({["] ]]; then
                    __Strings[$__level/${__Counts[$__level]}]+=" $'\0'--object--$'\0'"
                    __pos_to_level[$__idx]=$(( ++ __level ))
                    __level_to_pos[$__level]=$__idx
                    (( __Counts[$__level] += 1 ))
                    __sidx=__idx+1
                    __had_quoted_value=0
                elif [[ ${match[1]} = ["]})"] ]]; then
                    (( !__had_quoted_value )) && \
                        __Strings[$__level/${__Counts[$__level]}]+=" ${(q)__input[__sidx,__idx-1]//((#s)[[:blank:]]##|([[:blank:]]##(#e)))}"
                    __had_quoted_value=1
                    if (( __level > 0 )); then
                        __pair_idx=${__level_to_pos[$__level]}
                        __pos_to_level[$__idx]=$(( __level -- ))
                        [[ ${__pair_map[${__input[__pair_idx]}]} = ${__input[__idx]} ]] && {
                            __final_pairs[$__idx]=$__pair_idx
                            __final_pairs[$__pair_idx]=$__idx
                            __pair_order+=( $__idx )
                        }
                    else
                        __pos_to_level[$__idx]=-1
                    fi
                fi
            }

            [[ ${match[1]} = \" && $__quoting != \' ]] && \
                if [[ $__quoting = '"' ]]; then
                    __Strings[$__level/${__Counts[$__level]}]+=" ${(q)__input[__sidx,__idx-1]}"
                    __quoting=""
                else
                    __had_quoted_value=1
                    __sidx=__idx+1
                    __quoting='"'
                fi

            [[ ${match[1]} = , && -z $__quoting ]] && \
                {
                    (( !__had_quoted_value )) && \
                        __Strings[$__level/${__Counts[$__level]}]+=" ${(q)__input[__sidx,__idx-1]//((#s)[[:blank:]]##|([[:blank:]]##(#e)))}"
                    __sidx=__idx+1
                    __had_quoted_value=0
                }

            [[ ${match[1]} = : && -z $__quoting ]] && \
                {
                    __had_quoted_value=0
                    __sidx=__idx+1
                }

            [[ ${match[1]} = \' && $__quoting != \" ]] && \
                if [[ $__quoting = "'" ]]; then
                    __Strings[$__level/${__Counts[$__level]}]+=" ${(q)__input[__sidx,__idx-1]}"
                    __quoting=""
                else
                    __had_quoted_value=1
                    __sidx=__idx+1
                    __quoting="'"
                fi

            __workbuf=${match[4]}
        }
    done

    local __text __found
    if (( __nest != 2 )) {
        integer __pair_a __pair_b
        for __pair_a ( "${__pair_order[@]}" ) {
            __pair_b="${__final_pairs[$__pair_a]}"
            __text="${__input[__pair_b,__pair_a]}"
            if [[ $__text = [[:space:]]#\{[[:space:]]#[\"\']${__key}[\"\']* ]]; then
                __found="$__text"
            fi
        }
    }

    if [[ -n $__found && $__nest -lt 2 ]] {
        .zinit-parse-json "$__found" "$__key" "$__varname" 2
    }

    if (( __nest == 2 )) {
        : ${(PAA)__varname::="${(kv)__Strings[@]}"}
    }
}
# ]]]
# FUNCTION: .zinit-get-package [[[
.zinit-get-package() {
    emulate -LR zsh
    setopt extendedglob warncreateglobal typesetsilent noshortloops rcquotes

    local user="$1" plugin="$2" id_as="$3" dir="$4" profile="$5" \
        local_path="${ZINIT[PLUGINS_DIR]}/${3//\//---}" pkgjson \
        tmpfile="${$(mktemp):-/tmp/zsh.xYzAbc123}" \
        URL="https://raw.githubusercontent.com/Zsh-Packages/$2/master/package.json"

    print -P -- "\n%F{yellow}%B===%f Downloading ${ZINIT[col-info2]}package.json%f" \
        "for ${ZINIT[col-pname]}$plugin %F{yellow}===%f%b"

    if [[ $profile != ./* ]]; then
        .zinit-download-file-stdout $URL 2>/dev/null > $tmpfile || \
            { rm -f $tmpfile; .zinit-download-file-stdout $URL 1 2>/dev/null > $tmpfile }
    else
        tmpfile=${profile%:*}
        profile=${${${(M)profile:#*:*}:+${profile#*:}}:-default}
    fi

    pkgjson="$(<$tmpfile)"

    if [[ -z $pkgjson ]]; then
        print -r -- "${ZINIT[col-error]}Error: the package $id_as couldn't be found."
        return 1
    fi

    print -Pr -- "Parsing ${ZINIT[col-info2]}package.json%f%b..."

    local -A Strings
    .zinit-parse-json "$pkgjson" "plugin-info" Strings

    local -A jsondata1
    jsondata1=( ${(@Q)${(@z)Strings[2/1]}} )
    local user=${jsondata1[user]} plugin=${jsondata1[plugin]} \
        url=${jsondata1[url]} message=${jsondata1[message]} \
        required=${jsondata1[required]:-${jsondata1[requires]}}

    local -a profiles
    local key value
    integer pos
    profiles=( ${(@Q)${(@z)Strings[2/2]}} )
    profiles=( ${profiles[@]:#$'\0'--object--$'\0'} )
    pos=${${(@Q)${(@z)Strings[2/2]}}[(I)$profile]}
    if (( pos )) {
        for key value ( "${(@Q)${(@z)Strings[3/$(( (pos + 1) / 2 ))]}}" ) {
            (( ${+ZINIT_ICE[$key]} )) && [[ ${ZINIT_ICE[$key]} != +* ]] && continue
            ZINIT_ICE[$key]=$value${ZINIT_ICE[$key]#+}
        }
        ZINIT_ICE=( "${(kv)ZINIT_ICE[@]//\\\"/\"}" )
        [[ ${ZINIT_ICE[as]} = program ]] && ZINIT_ICE[as]="command"
        [[ -n ${ZINIT_ICE[on-update-of]} ]] && ZINIT_ICE[subscribe]="${ZINIT_ICE[subscribe]:-${ZINIT_ICE[on-update-of]}}"
        [[ -n ${ZINIT_ICE[pick]} ]] && ZINIT_ICE[pick]="${ZINIT_ICE[pick]//\$ZPFX/${ZPFX%/}}"
        [[ -n ${ZINIT_ICE[id-as]} ]] && {
            @zinit-substitute 'ZINIT_ICE[id-as]'
            local -A map
            map=( "\"" "\\\"" "\\" "\\" )
            eval "ZINIT_ICE[id-as]=\"${ZINIT_ICE[id-as]//(#m)[\"\\]/${map[$MATCH]}}\""
        }
    } else {
        print -P -r -- "${ZINIT[col-error]}Error: the profile \`%F{221}$profile${ZINIT[col-error]}' couldn't be found, aborting.%f%b"
        print -r -- "Available profiles are: ${(j:, :)${profiles[@]:#$profile}}."
        return 1
    }

    print -Pr -- "Found the profile \`${ZINIT[col-pname]}$profile%f%b'."

    ZINIT_ICE[required]=${ZINIT_ICE[required]:-$ZINIT_ICE[requires]}
    local -a req
    req=( ${(s.;.)${:-${required:+$required\;}${ZINIT_ICE[required]}}} )
    for required ( $req ) {
        if [[ $required == (bgn|dl|monitor) ]]; then
            if [[ ( $required == bgn && -z ${(k)ZINIT_EXTS[(r)<-> z-annex-data: z-a-bin-gem-node *]} ) || \
                ( $required == dl && -z ${(k)ZINIT_EXTS[(r)<-> z-annex-data: z-a-patch-dl *]} ) || \
                ( $required == monitor && -z ${(k)ZINIT_EXTS[(r)<-> z-annex-data: z-a-as-monitor *]} )
            ]]; then
                local -A namemap
                namemap=( bgn Bin-Gem-Node dl Patch-Dl monitor As-Monitor )
                print -P -- "${ZINIT[col-error]}ERROR: the" \
                    "${${${(MS)ZINIT_ICE[required]##(\;|(#s))$required(\;|(#e))}:+selected profile}:-package}" \
                    "${${${(MS)ZINIT_ICE[required]##(\;|(#s))$required(\;|(#e))}:+\`${ZINIT[col-pname]}$profile${ZINIT[col-error]}\'}:-\\b}" \
                    "requires ${namemap[$required]} annex." \
                    "\nSee: %F{221}https://github.com/zinit-zsh/z-a-${(L)namemap[$required]}%f%b."
                (( ${#profiles[@]:#$profile} > 0 )) && print -r -- "Other available profiles are: ${(j:, :)${profiles[@]:#$profile}}."
                return 1
            fi
        else
            if ! command -v $required &>/dev/null; then
                print -P -- "${ZINIT[col-error]}ERROR: the" \
                    "${${${(MS)ZINIT_ICE[required]##(\;|(#s))$required(\;|(#e))}:+selected profile}:-package}" \
                    "${${${(MS)ZINIT_ICE[required]##(\;|(#s))$required(\;|(#e))}:+\`${ZINIT[col-pname]}$profile${ZINIT[col-error]}\'}:-\\b}" \
                    "requires" \
                    "\`${ZINIT[col-pname]}$required${ZINIT[col-error]}' command.%f%b"
                print -r -- "Other available profiles are: ${(j:, :)${profiles[@]:#$profile}}."
                return 1
            fi
        fi
    }

    if [[ -n ${ZINIT_ICE[dl]} && -z ${(k)ZINIT_EXTS[(r)<-> z-annex-data: z-a-patch-dl *]} ]] {
        print -P -- "\n${ZINIT[col-error]}WARNING:${ZINIT[col-msg2]} the profile uses" \
            "${ZINIT[col-obj]}dl''${ZINIT[col-msg2]} ice however there's no" \
            "${ZINIT[col-obj2]}z-a-patch-dl${ZINIT[col-msg2]} annex loaded" \
            "(the ice will be inactive, i.e.: no additional files will" \
            "become downloaded).%f%b"
    }

    print -Pn -- ${jsondata1[version]:+\\n${ZINIT[col-pname]}Version: ${ZINIT[col-info2]}${jsondata1[version]}%f%b.\\n}
    [[ -n ${jsondata1[message]} ]] && \
        print -P -- "${ZINIT[col-info]}${jsondata1[message]}%f%b"

    (( ${+ZINIT_ICE[is-snippet]} )) && {
        reply=( "" "$url" )
        REPLY=snippet
        return 0
    }

    if (( !${+ZINIT_ICE[git]} && !${+ZINIT_ICE[from]} )) {
        (
            .zinit-parse-json "$pkgjson" "_from" Strings
            local -A jsondata
            jsondata=( "${(@Q)${(@z)Strings[1/1]}}" )

            local URL=${jsondata[_resolved]}
            local fname="${${URL%%\?*}:t}"

            command mkdir -p $dir || {
                print -Pr -- "${ZINIT[col-error]}Couldn't create directory:" \
                    "\`${ZINIT[col-msg2]}$dir${ZINIT[col-error]}', aborting.%f%b"
                return 1
            }
            builtin cd -q $dir || return 1

            print -Pr -- "Downloading tarball for ${ZINIT[col-pname]}$plugin%f%b..."

            .zinit-download-file-stdout "$URL" >! "$fname" || {
                .zinit-download-file-stdout "$URL" 1 >! "$fname" || {
                    command rm -f "$fname"
                    print -r "Download of \`$fname' failed. No available download tool? (one of: cURL, wget, lftp, lynx)"
                    return 1
                }
            }

            ziextract "$fname" --move
            return 0
        ) && {
            reply=( "$user" "$plugin" )
            REPLY=tarball
        }
    } else {
            reply=( "${ZINIT_ICE[user]:-$user}" "${ZINIT_ICE[plugin]:-$plugin}" )
            if [[ ${ZINIT_ICE[from]} = (|gh-r|github-rel) ]]; then
                REPLY=github
            else
                REPLY=unknown
            fi
    }

    return $?
}
# ]]]
# FUNCTION: .zinit-setup-plugin-dir [[[
# Clones given plugin into PLUGIN_DIR. Supports multiple
# sites (respecting `from' and `proto' ice modifiers).
# Invokes compilation of plugin's main file.
#
# $1 - user
# $2 - plugin
.zinit-setup-plugin-dir() {
    emulate -LR zsh
    setopt extendedglob warncreateglobal noshortloops rcquotes

    local user=$1 plugin=$2 id_as=$3 remote_url_path=${1:+$1/}$2 \
        local_path tpe=$4 update=$5 version=$6

    if .zinit-get-object-path plugin "$id_as" && [[ -z $update ]] {
        print -Pr "$ZINIT[col-msg2]A plugin named $ZINIT[col-obj]$id_as" \
            "$ZINIT[col-msg2]already exists, aborting.%f%b"
        return 1
    }
    local_path=$reply[-3]

    local -A sites
    sites=(
        github    github.com
        gh        github.com
        bitbucket bitbucket.org
        bb        bitbucket.org
        gitlab    gitlab.com
        gl        gitlab.com
        notabug   notabug.org
        nb        notabug.org
        github-rel github.com/$remote_url_path/releases
        gh-r      github.com/$remote_url_path/releases
    )

    ZINIT[annex-multi-flag:pull-active]=${${${(M)update:#-u}:+${ZINIT[annex-multi-flag:pull-active]}}:-2}

    local -a arr

    if [[ $user = _local ]]; then
        print "Warning: no local plugin \`$plugin\'."
        print "(should be located at: $local_path)"
        return 1
    fi

    command rm -f /tmp/zinit-execs.$$.lst

    [[ $tpe != tarball ]] && {
        [[ -z $update ]] && {
            .zinit-any-colorify-as-uspl2 "$user" "$plugin"
            print "\\nDownloading $REPLY...${id_as:+ (as ${id_as}...)}"
        }

        local site
        [[ -n ${ZINIT_ICE[from]} ]] && site=${sites[${ZINIT_ICE[from]}]}
        [[ -z $site && ${ZINIT_ICE[from]} = *(gh-r|github-rel)* ]] && {
            site=${ZINIT_ICE[from]/(gh-r|github-re)/${sites[gh-r]}}
        }
    }

    (
        if [[ $site = *releases ]] {
            local url=$site/${ZINIT_ICE[ver]}

            .zinit-get-latest-gh-r-url-part "$user" "$plugin" "$url" || return $?

            command mkdir -p "$local_path"
            [[ -d "$local_path" ]] || return 1

            (
                () { setopt localoptions noautopushd; builtin cd -q "$local_path"; } || return 1
                url="https://github.com${REPLY}"
                if [[ -d $local_path/._zinit ]] {
                    { local old_version="$(<$local_path/._zinit/is_release)"; } 2>/dev/null
                    old_version=${old_version/(#b)(\/[^\/]##)(#c4,4)\/([^\/]##)*/${match[2]}}
                }
                print "(Requesting \`${REPLY:t}'${version:+, version $version}...${old_version:+ Current version: $old_version.})"
                if { ! .zinit-download-file-stdout "$url" >! "${REPLY:t}" } {
                    if { ! .zinit-download-file-stdout "$url" 1 >! "${REPLY:t}" } {
                        command rm -f "${REPLY:t}"
                        print -r "Download of release for \`$remote_url_path' failed. No available download tool? (one of: curl, wget, lftp, lynx)"
                        print -r "Tried url: $url."
                        return 1
                    }
                }
                if .zinit-download-file-stdout "$url.sig" 2>/dev/null >! "${REPLY:t}.sig"; then
                    :
                fi

                command mkdir -p ._zinit
                [[ -d ._zinit ]] || return 2
                print -r -- $url >! ._zinit/url || return 3
                print -r -- ${REPLY} >! ._zinit/is_release || return 4
                ziextract ${REPLY:t}
                return $?
            ) || {
                return 1
            }
        } elif [[ $tpe = github ]] {
            case ${ZINIT_ICE[proto]} in
                (|https|git|http|ftp|ftps|rsync|ssh)
                    command git clone --progress ${=ZINIT_ICE[cloneopts]:---recursive} \
                        ${=ZINIT_ICE[depth]:+--depth ${ZINIT_ICE[depth]}} \
                        "${ZINIT_ICE[proto]:-https}://${site:-${ZINIT_ICE[from]:-github.com}}/$remote_url_path" \
                        "$local_path" \
                        --config transfer.fsckobjects=false \
                        --config receive.fsckobjects=false \
                        --config fetch.fsckobjects=false \
                            |& { ${ZINIT[BIN_DIR]}/git-process-output.zsh || cat; }
                    (( pipestatus[1] )) && { print -Pr -- "${ZINIT[col-error]}Clone failed (code: ${pipestatus[1]}).%f%b"; return 1; }
                    ;;
                (*)
                    print -Pr "${ZINIT[col-error]}Unknown protocol:%f%b ${ZINIT_ICE[proto]}."
                    return 1
            esac

            if [[ -n ${ZINIT_ICE[ver]} ]] {
                command git -C "$local_path" checkout "${ZINIT_ICE[ver]}"
            }
        }

        [[ ${+ZINIT_ICE[make]} = 1 && ${ZINIT_ICE[make]} = "!!"* ]] && .zinit-countdown make && { local make=${ZINIT_ICE[make]}; @zinit-substitute make; command make -C "$local_path" ${(@s; ;)${make#\!\!}}; }

        if [[ -n ${ZINIT_ICE[mv]} ]] {
            if [[ ${ZINIT_ICE[mv]} = *("->"|"→")* ]] {
                local from=${ZINIT_ICE[mv]%%[[:space:]]#(->|→)*} to=${ZINIT_ICE[mv]##*(->|→)[[:space:]]#} || \
            } else {
                local from=${ZINIT_ICE[mv]%%[[:space:]]##*} to=${ZINIT_ICE[mv]##*[[:space:]]##}
            }
            @zinit-substitute from to
            local -a afr
            ( () { setopt localoptions noautopushd; builtin cd -q "$local_path"; } || return 1
              afr=( ${~from}(DN) )
              if (( ${#afr} )) {
                  if (( !ICE_OPTS[opt_-q,--quiet] )) {
                      command mv -vf "${afr[1]}" "$to"
                      command mv -vf "${afr[1]}".zwc "$to".zwc 2>/dev/null
                  } else {
                      command mv -f "${afr[1]}" "$to"
                      command mv -f "${afr[1]}".zwc "$to".zwc 2>/dev/null
                  }
              }
            )
        }

        if [[ -n ${ZINIT_ICE[cp]} ]] {
            if [[ ${ZINIT_ICE[cp]} = *("->"|"→")* ]] {
                local from=${ZINIT_ICE[cp]%%[[:space:]]#(->|→)*} to=${ZINIT_ICE[cp]##*(->|→)[[:space:]]#} || \
            } else {
                local from=${ZINIT_ICE[cp]%%[[:space:]]##*} to=${ZINIT_ICE[cp]##*[[:space:]]##}
            }
            @zinit-substitute from to
            local -a afr
            ( () { setopt localoptions noautopushd; builtin cd -q "$local_path"; } || return 1
              afr=( ${~from}(DN) )
              if (( ${#afr} )) {
                  if (( !ICE_OPTS[opt_-q,--quiet] )) {
                      command cp -vf "${afr[1]}" "$to"
                      command cp -vf "${afr[1]}".zwc "$to".zwc 2>/dev/null
                  } else {
                      command cp -f "${afr[1]}" "$to"
                      command cp -f "${afr[1]}".zwc "$to".zwc 2>/dev/null
                  }
              }
            )
        }

        if [[ $site != *releases && ${ZINIT_ICE[nocompile]} != '!' ]] {
            # Compile plugin
            [[ -z ${ZINIT_ICE[(i)(\!|)(sh|bash|ksh|csh)]} ]] && {
                () {
                    emulate -LR zsh
                    setopt extendedglob warncreateglobal
                    .zinit-compile-plugin "$id_as" ""
                }
            }
        }

        if [[ $update != -u ]] {
            # Store ices at clone of a plugin
            .zinit-store-ices "$local_path/._zinit" ZINIT_ICE "" "" "" ""

            reply=( "${(@on)ZINIT_EXTS[(I)z-annex hook:\\\!atclone <->]}" )
            for key in "${reply[@]}"; do
                arr=( "${(Q)${(z@)ZINIT_EXTS[$key]}[@]}" )
                "${arr[5]}" "plugin" "$user" "$plugin" "$id_as" "$local_path" \!atclone
            done

            local atclone=${ZINIT_ICE[atclone]} extract=${ZINIT_ICE[extract]}
            @zinit-substitute atclone extract

            [[ ${+ZINIT_ICE[make]} = 1 && ${ZINIT_ICE[make]} = ("!"[^\!]*|"!") ]] && .zinit-countdown make && { local make=${ZINIT_ICE[make]}; @zinit-substitute make; command make -C "$local_path" ${(@s; ;)${make#\!}}; }
            [[ -n $atclone ]] && .zinit-countdown atclone && { local __oldcd=$PWD; (( ${+ZINIT_ICE[nocd]} == 0 )) && { () { setopt localoptions noautopushd; builtin cd -q "$local_path"; } && eval "$atclone"; ((1)); } || eval "$atclone"; () { setopt localoptions noautopushd; builtin cd -q "$__oldcd"; }; }
            [[ ${+ZINIT_ICE[make]} = 1 && ${ZINIT_ICE[make]} != "!"* ]] && .zinit-countdown make && { local make=${ZINIT_ICE[make]}; @zinit-substitute make; command make -C "$local_path" ${(@s; ;)make}; }

            if (( ${+ZINIT_ICE[extract]} )) {
                .zinit-extract plugin "$extract" "$local_path"
            }

            # Run annexes' atclone hooks (the after atclone-ice ones)
            reply=( "${(@on)ZINIT_EXTS[(I)z-annex hook:atclone <->]}" )
            for key in "${reply[@]}"; do
                arr=( "${(Q)${(z@)ZINIT_EXTS[$key]}[@]}" )
                "${arr[5]}" "plugin" "$user" "$plugin" "$id_as" "$local_path" atclone
            done
        }

        if [[ $site != *releases && ${ZINIT_ICE[nocompile]} = '!' ]] {
            # Compile plugin
            LANG=C sleep 0.3
            [[ -z ${ZINIT_ICE[(i)(\!|)(sh|bash|ksh|csh)]} ]] && {
                () {
                    emulate -LR zsh
                    setopt extendedglob warncreateglobal
                    .zinit-compile-plugin "$id_as" ""
                }
            }
        }
    ) || return $?

    typeset -ga INSTALLED_EXECS
    { INSTALLED_EXECS=( "${(@f)$(</tmp/zinit-execs.lst)}" ) } 2>/dev/null
    command rm -f /tmp/zinit-execs.$$.lst

    # After additional executions like atclone'' - install completions (1 - plugins)
    local -A ICE_OPTS
    ICE_OPTS[opt_-q,--quiet]=1
    [[ 1 = ${+ZINIT_ICE[nocompletions]} || ${ZINIT_ICE[as]} = null ]] || \
        .zinit-install-completions "$id_as" "" "0"

    return 0
} # ]]]
# FUNCTION: .zinit-install-completions [[[
# Installs all completions of given plugin. After that they are
# visible to `compinit'. Visible completions can be selectively
# disabled and enabled. User can access completion data with
# `clist' or `completions' subcommand.
#
# $1 - plugin spec (4 formats: user---plugin, user/plugin, user, plugin)
# $2 - plugin (only when $1 - i.e. user - given)
# $3 - if 1, then reinstall, otherwise only install completions that aren't there
.zinit-install-completions() {
    builtin setopt localoptions nullglob extendedglob unset nokshglob warncreateglobal

    # $id_as - a /-separated pair if second element
    # is not empty and first is not "%" - then it's
    # just $1 in first case, or $1$2 in second case
    local id_as="$1${2:+${${${(M)1:#%}:+$2}:-/$2}}" reinstall="${3:-0}" quiet="${${4:+1}:-0}"
    (( ICE_OPTS[opt_-q,--quiet] )) && quiet=1
    typeset -ga INSTALLED_COMPS SKIPPED_COMPS
    INSTALLED_COMPS=() SKIPPED_COMPS=()

    .zinit-any-to-user-plugin "$id_as" ""
    local user="${reply[-2]}"
    local plugin="${reply[-1]}"
    .zinit-any-colorify-as-uspl2 "$user" "$plugin"
    local abbrev_pspec="$REPLY"

    .zinit-exists-physically-message "$id_as" "" || return 1

    # Symlink any completion files included in plugin's directory
    typeset -a completions already_symlinked backup_comps
    local c cfile bkpfile
    [[ "$user" = "%" ]] && \
        completions=( "${plugin}"/**/_[^_.]*~*(*.zwc|*.html|*.txt|*.png|*.jpg|*.jpeg|*.js|*.md|*.yml|*.ri|_zsh_highlight*|/zsdoc/*)(DN^/) ) || \
        completions=( "${ZINIT[PLUGINS_DIR]}/${id_as//\//---}"/**/_[^_.]*~*(*.zwc|*.html|*.txt|*.png|*.jpg|*.jpeg|*.js|*.md|*.yml|*.ri|_zsh_highlight*|/zsdoc/*)(DN^/) )
    already_symlinked=( "${ZINIT[COMPLETIONS_DIR]}"/_[^_.]*~*.zwc(DN) )
    backup_comps=( "${ZINIT[COMPLETIONS_DIR]}"/[^_.]*~*.zwc(DN) )

    # Symlink completions if they are not already there
    # either as completions (_fname) or as backups (fname)
    # OR - if it's a reinstall
    for c in "${completions[@]}"; do
        cfile="${c:t}"
        bkpfile="${cfile#_}"
        if [[ -z "${already_symlinked[(r)*/$cfile]}" &&
              -z "${backup_comps[(r)*/$bkpfile]}" ||
              "$reinstall" = "1"
        ]]; then
            if [[ "$reinstall" = "1" ]]; then
                # Remove old files
                command rm -f "${ZINIT[COMPLETIONS_DIR]}/$cfile"
                command rm -f "${ZINIT[COMPLETIONS_DIR]}/$bkpfile"
            fi
            INSTALLED_COMPS+=( $cfile )
            (( quiet )) || print -Pr "Symlinking completion ${ZINIT[col-uname]}$cfile%f%b to completions directory."
            command ln -fs "$c" "${ZINIT[COMPLETIONS_DIR]}/$cfile"
            # Make compinit notice the change
            .zinit-forget-completion "$cfile" "$quiet"
        else
            SKIPPED_COMPS+=( $cfile )
            (( quiet )) || print -Pr "Not symlinking completion \`${ZINIT[col-obj]}$cfile%f%b', it already exists."
            (( quiet )) || print -Pr "${ZINIT[col-info2]}Use \`${ZINIT[col-pname]}zinit creinstall $abbrev_pspec${ZINIT[col-info2]}' to force install.%f%b"
        fi
    done

    (( quiet && (${#INSTALLED_COMPS} || ${#SKIPPED_COMPS}) )) && {
        print -r "${ZINIT[col-msg1]}Installed ${ZINIT[col-obj]}${#INSTALLED_COMPS}" \
            "${ZINIT[col-msg1]}completions. They are stored in${ZINIT[col-obj2]}" \
            "\$INSTALLED_COMPS${ZINIT[col-msg1]} array.${ZINIT[col-rst]}"
        if (( ${#SKIPPED_COMPS} )) {
            print -r "${ZINIT[col-msg1]}Skipped installing" \
                "${ZINIT[col-obj]}${#SKIPPED_COMPS}${ZINIT[col-msg1]} completions." \
                "They are stored in ${ZINIT[col-obj2]}\$SKIPPED_COMPS${ZINIT[col-msg1]} array." \
                ${ZINIT[col-rst]}
        }
    }

    .zinit-compinit &>/dev/null
} # ]]]
# FUNCTION: .zinit-compinit [[[
# User-exposed `compinit' frontend which first ensures that all
# completions managed by Zinit are forgotten by Zshell. After
# that it runs normal `compinit', which should more easily detect
# Zinit's completions.
#
# No arguments.
.zinit-compinit() {
    builtin setopt localoptions nullglob extendedglob nokshglob noksharrays warncreateglobal

    typeset -a symlinked backup_comps
    local c cfile bkpfile action

    symlinked=( "${ZINIT[COMPLETIONS_DIR]}"/_[^_.]*~*.zwc )
    backup_comps=( "${ZINIT[COMPLETIONS_DIR]}"/[^_.]*~*.zwc )

    # Delete completions if they are really there, either
    # as completions (_fname) or backups (fname)
    for c in "${symlinked[@]}" "${backup_comps[@]}"; do
        action=0
        cfile="${c:t}"
        cfile="_${cfile#_}"
        bkpfile="${cfile#_}"

        #print -Pr "${ZINIT[col-info]}Processing completion $cfile%f%b"
        .zinit-forget-completion "$cfile"
    done

    print "Initializing completion (compinit)..."
    command rm -f ${ZINIT[ZCOMPDUMP_PATH]:-${ZDOTDIR:-$HOME}/.zcompdump}

    # Workaround for a nasty trick in _vim
    (( ${+functions[_vim_files]} )) && unfunction _vim_files

    builtin autoload -Uz compinit
    compinit -d ${ZINIT[ZCOMPDUMP_PATH]:-${ZDOTDIR:-$HOME}/.zcompdump} "${(Q@)${(z@)ZINIT[COMPINIT_OPTS]}}"
} # ]]]
# FUNCTION: .zinit-download-file-stdout [[[
# Downloads file to stdout. Supports following backend commands:
# curl, wget, lftp, lynx. Used by snippet loading.
.zinit-download-file-stdout() {
    local url="$1" restart="$2"

    setopt localoptions localtraps

    if (( restart )); then
        (( ${path[(I)/usr/local/bin]} )) || \
            {
                path+=( "/usr/local/bin" );
                trap "path[-1]=()" EXIT
            }

        if (( ${+commands[curl]} )) then
            command curl -fsSL "$url" || return 1
        elif (( ${+commands[wget]} )); then
            command wget -q "$url" -O - || return 1
        elif (( ${+commands[lftp]} )); then
            command lftp -c "cat $url" || return 1
        elif (( ${+commands[lynx]} )) then
            command lynx -source "$url" || return 1
        else
            return 2
        fi
    else
        if type curl 2>/dev/null 1>&2; then
            command curl -fsSL "$url" || return 1
        elif type wget 2>/dev/null 1>&2; then
            command wget -q "$url" -O - || return 1
        elif type lftp 2>/dev/null 1>&2; then
            command lftp -c "cat $url" || return 1
        else
            .zinit-download-file-stdout "$url" "1"
            return $?
        fi
    fi

    return 0
} # ]]]
# FUNCTION: .zinit-get-url-mtime [[[
# For the given URL returns the date in the Last-Modified
# header as a time stamp
.zinit-get-url-mtime() {
    local url="$1" IFS line header
    local -a cmd

    setopt localoptions localtraps

    (( !${path[(I)/usr/local/bin]} )) && \
        {
            path+=( "/usr/local/bin" );
            trap "path[-1]=()" EXIT
        }

    if (( ${+commands[curl]} )) || type curl 2>/dev/null 1>&2; then
        cmd=(command curl -sIL "$url")
    elif (( ${+commands[wget]} )) || type wget 2>/dev/null 1>&2; then
        cmd=(command wget --server-response --spider -q "$url" -O -)
    else
        REPLY=$(( $(date +"%s") ))
        return 2
    fi

    "${cmd[@]}" |& command grep Last-Modified: | while read -r line; do
        header="${line#*, }"
    done

    [[ -z $header ]] && {
        REPLY=$(( $(date +"%s") ))
        return 3
    }
    
    LANG=C strftime -r -s REPLY "%d %b %Y %H:%M:%S GMT" "$header" &>/dev/null || {
        REPLY=$(( $(date +"%s") ))
        return 4
    }

    return 0
} # ]]]
# FUNCTION: .zinit-mirror-using-svn [[[
# Used to clone subdirectories from Github. If in update mode
# (see $2), then invokes `svn update', in normal mode invokes
# `svn checkout --non-interactive -q <URL>'. In test mode only
# compares remote and local revision and outputs true if update
# is needed.
#
# $1 - URL
# $2 - mode, "" - normal, "-u" - update, "-t" - test
# $3 - subdirectory (not path) with working copy, needed for -t and -u
.zinit-mirror-using-svn() {
    setopt localoptions extendedglob warncreateglobal
    local url="$1" update="$2" directory="$3"

    (( ${+commands[svn]} )) || \
        print -Pr -- "${ZINIT[col-error]}Warning:%f%b Subversion not found" \
            ", please install it to use \`${ZINIT[col-obj]}svn%f%b' ice."

    if [[ "$update" = "-t" ]]; then
        (
            () { setopt localoptions noautopushd; builtin cd -q "$directory"; }
            local -a out1 out2
            out1=( "${(f@)"$(LANG=C svn info -r HEAD)"}" )
            out2=( "${(f@)"$(LANG=C svn info)"}" )

            out1=( "${(M)out1[@]:#Revision:*}" )
            out2=( "${(M)out2[@]:#Revision:*}" )
            [[ "${out1[1]##[^0-9]##}" != "${out2[1]##[^0-9]##}" ]] && return 0
            return 1
        )
        return $?
    fi
    if [[ "$update" = "-u" && -d "$directory" && -d "$directory/.svn" ]]; then
        ( () { setopt localoptions noautopushd; builtin cd -q "$directory"; }
          command svn update
          return $? )
    else
        command svn checkout --non-interactive -q "$url" "$directory"
    fi
    return $?
}
# ]]]
# FUNCTION: .zinit-forget-completion [[[
# Implements alternation of Zsh state so that already initialized
# completion stops being visible to Zsh.
#
# $1 - completion function name, e.g. "_cp"; can also be "cp"
.zinit-forget-completion() {
    emulate -LR zsh
    setopt extendedglob typesetsilent warncreateglobal

    local f="$1" quiet="$2"

    typeset -a commands
    commands=( ${(k)_comps[(Re)$f]} )

    [[ "${#commands}" -gt 0 ]] && (( quiet == 0 )) && print -Prn "Forgetting commands completed by \`${ZINIT[col-obj]}$f%f%b': "

    local k
    integer first=1
    for k ( $commands ) {
        unset "_comps[$k]"
        (( quiet )) || print -Prn "${${first:#1}:+, }${ZINIT[col-info]}$k%f%b"
        first=0
    }
    (( quiet || first )) || print

    unfunction -- 2>/dev/null "$f"
} # ]]]
# FUNCTION: .zinit-compile-plugin [[[
# Compiles given plugin (its main source file, and also an
# additional "....zsh" file if it exists).
#
# $1 - plugin spec (4 formats: user---plugin, user/plugin, user, plugin)
# $2 - plugin (only when $1 - i.e. user - given)
.zinit-compile-plugin() {
    # $id_as - a /-separated pair if second element
    # is not empty and first is not "%" - then it's
    # just $1 in first case, or $1$2 in second case
    local id_as="$1${2:+${${${(M)1:#%}:+$2}:-/$2}}" first plugin_dir filename is_snippet
    local -a list

    local -A ICE
    .zinit-compute-ice "$id_as" "pack" \
        ICE plugin_dir filename is_snippet || return 1

    [[ "${ICE[pick]}" = "/dev/null" ]] && return 0

    if [[ ${ICE[as]} != "command" && ( ${+ICE[nocompile]} = "0" || ${ICE[nocompile]} = "!" ) ]]; then
        if [[ -n "${ICE[pick]}" ]]; then
            list=( ${~${(M)ICE[pick]:#/*}:-$plugin_dir/$ICE[pick]}(DN) )
            [[ ${#list} -eq 0 ]] && {
                print "No files for compilation found (pick-ice didn't match)."
                return 1
            }
            reply=( "${list[1]:h}" "${list[1]}" )
        else
            if (( is_snippet )) {
                .zinit-first "%" "$plugin_dir" || {
                    [[ ${ZINIT_ICE[as]} != null ]] && \
                        print "No files for compilation found."
                    return 1
                }
            } else {
                .zinit-first "$1" "$2" || {
                    [[ ${ZINIT_ICE[as]} != null ]] && \
                        print "No files for compilation found."
                    return 1
                }
            }
        fi
        local pdir_path="${reply[-2]}"
        first="${reply[-1]}"
        local fname="${first#$pdir_path/}"

        print -Pr "Compiling ${ZINIT[col-info]}$fname%f%b."
        [[ -z ${ICE[(i)(\!|)(sh|bash|ksh|csh)]} ]] && {
            zcompile "$first" || {
                print "Compilation failed. Don't worry, the plugin will work also without compilation"
                print "Consider submitting an error report to Zinit or to the plugin's author."
            }
        }
        # Try to catch possible additional file
        zcompile "${${first%.plugin.zsh}%.zsh-theme}.zsh" 2>/dev/null
    fi

    if [[ -n "${ICE[compile]}" ]]; then
        eval "list=( \$plugin_dir/${~ICE[compile]}(DN) )"
        [[ ${#list} -eq 0 ]] && {
            print "Warning: ice compile'' didn't match any files."
        } || {
            for first in "${list[@]}"; do
                zcompile "$first"
            done
            local sep="${ZINIT[col-pname]},${ZINIT[col-rst]} "
            print -Pr -- "Compiled following additional files (${ZINIT[col-pname]}the compile''-ice%f%b: ${(pj:$sep:)${(@)${list[@]//(#b).([^.\/]##(#e))/.${ZINIT[col-info]}${match[1]}${ZINIT[col-rst]}}#$plugin_dir/}}."
        }
    fi

    return 0
} # ]]]
# FUNCTION: .zinit-download-snippet [[[
# Downloads snippet – either a file – with curl, wget, lftp or lynx,
# or a directory, with Subversion – when svn-ICE is active. Github
# supports Subversion protocol and allows to clone subdirectories.
# This is used to provide a layer of support for Oh-My-Zsh and Prezto.
.zinit-download-snippet() {
    emulate -LR zsh
    setopt extendedglob warncreateglobal typesetsilent

    local save_url="$1" url="$2" id_as="$3" id_as_clean="${3%%\?*}" local_dir="$4" dirname="$5" filename="$6" update="$7"
    local -a list arr
    integer retval=0
    [[ $id_as = (http|https|ftp|ftps|scp)://* ]] && {
        local sname="${${id_as_clean:h}:t}/${id_as_clean:t}"
        [[ $sname = */trunk* ]] && sname=${${id_as_clean%%/trunk*}:t}/${id_as_clean:t}
    } || local sname="$id_as_clean"

    # Change the url to point to raw github content if it isn't like that
    [[ "$url" = *github.com* && ! "$url" = */raw/* && "${+ZINIT_ICE[svn]}" = "0" ]] && url="${url/\/blob\///raw/}"

    if [[ ! -d $local_dir/$dirname ]]; then
        [[ $update != -u ]] && print -P "\n${ZINIT[col-info]}Setting up snippet ${ZINIT[col-p]}${(l:10:: :)}$sname%f%b${ZINIT_ICE[id-as]:+... (as $id_as)}"
        command mkdir -p "$local_dir"
    fi

    [[ $update = -u && ${ICE_OPTS[opt_-q,--quiet]} != 1 ]] && print -Pr -- $'\n'"${ZINIT[col-info]}Updating snippet ${ZINIT[col-p]}$sname%f%b${ZINIT_ICE[id-as]:+... (identified as: $id_as)}"

    command rm -f /tmp/zinit-execs.$$.lst

    # A flag for the annexes. 0 – no new commits, 1 - run-atpull mode,
    # 2 – full update/there are new commits to download, 3 - full but
    # a forced download (i.e.: the medium doesn't allow to peek update)
    ZINIT[annex-multi-flag:pull-active]=${${${(M)update:#-u}:+${ZINIT[annex-multi-flag:pull-active]}}:-2}

    (
        if [[ $url = (http|https|ftp|ftps|scp)://* ]] {
            # URL
            (
                () { setopt localoptions noautopushd; builtin cd -q "$local_dir"; } || return 4

                (( !ICE_OPTS[opt_-q,--quiet] )) && print "Downloading \`$sname'${${ZINIT_ICE[svn]+ \(with Subversion\)}:- \(with curl, wget, lftp\)}..."

                if (( ${+ZINIT_ICE[svn]} )) {
                    local skip_pull=0
                    if [[ $update = -u ]] {
                        # Test if update available
                        .zinit-mirror-using-svn "$url" "-t" "$dirname" || {
                            (( ${+ZINIT_ICE[run-atpull]} )) && {
                                skip_pull=1
                            } || return 0 # Will return when no updates so atpull''
                                          # code below doesn't need any checks
                        }
                        ZINIT[annex-multi-flag:pull-active]=$(( 2 - skip_pull ))

                        (( !skip_pull )) && [[ "${ICE_OPTS[opt_-r,--reset]}" = 1 && -d "$filename/.svn" ]] && {
                            print -P "${ZINIT[col-msg2]}Resetting the repository (-r/--reset given)...%f%b"
                            command svn revert --recursive $filename/.
                        }

                        # Run annexes' atpull hooks (the before atpull-ice ones)
                        [[ ${ZINIT_ICE[atpull][1]} = *"!"* ]] && {
                            reply=( "${(@on)ZINIT_EXTS[(I)z-annex hook:\\\!atpull <->]}" )
                            for key in "${reply[@]}"; do
                                arr=( "${(Q)${(z@)ZINIT_EXTS[$key]}[@]}" )
                                "${arr[5]}" "snippet" "$save_url" "$id_as" "$local_dir/$dirname" \!atpull

                            done
                        }

                        (( ${+ZINIT_ICE[reset]} )) && (
                            (( !ICE_OPTS[opt_-q,--quiet] )) && print -P "%F{220}reset: running ${ZINIT_ICE[reset]:-svn revert --recursive $filename/.}%f%b"
                            eval "${ZINIT_ICE[reset]:-command svn revert --recursive $filename/.}"
                        )

                        [[ ${ZINIT_ICE[atpull][1]} = *"!"* ]] && .zinit-countdown atpull && { local __oldcd=$PWD; (( ${+ZINIT_ICE[nocd]} == 0 )) && { () { setopt localoptions noautopushd; builtin cd -q "$local_dir/$dirname"; } && .zinit-at-eval "${ZINIT_ICE[atpull]#!}" ${ZINIT_ICE[atclone]}; ((1)); } || .zinit-at-eval "${ZINIT_ICE[atpull]#!}" ${ZINIT_ICE[atclone]}; () { setopt localoptions noautopushd; builtin cd -q "$__oldcd"; };}

                        if (( !skip_pull )) {
                            # Do the update
                            # The condition is reversed on purpose – to show only
                            # the messages on an actual update
                            (( ICE_OPTS[opt_-q,--quiet] )) && {
                                print -Pr -- $'\n'"${ZINIT[col-info]}Updating snippet ${ZINIT[col-p]}$sname%f%b${ZINIT_ICE[id-as]:+... (identified as: $id_as)}"
                                print "Downloading \`$sname' (with Subversion)..."
                            }
                            .zinit-mirror-using-svn "$url" "-u" "$dirname" || return 4
                        }
                    } else {
                        .zinit-mirror-using-svn "$url" "" "$dirname" || return 4
                    }

                    # Redundant code, just to compile SVN snippet
                    if [[ ${ZINIT_ICE[as]} != command ]]; then
                        if [[ -n ${ZINIT_ICE[pick]} ]]; then
                            list=( ${(M)~ZINIT_ICE[pick]##/*}(DN) $local_dir/$dirname/${~ZINIT_ICE[pick]}(DN) )
                        elif [[ -z ${ZINIT_ICE[pick]} ]]; then
                            list=(
                                $local_dir/$dirname/*.plugin.zsh(DN) $local_dir/$dirname/*.zsh-theme(DN) $local_dir/$dirname/init.zsh(DN)
                                $local_dir/$dirname/*.zsh(DN) $local_dir/$dirname/*.sh(DN) $local_dir/$dirname/.zshrc(DN)
                            )
                        fi

                        [[ -e ${list[1]} && ${list[1]} != */dev/null && \
                            -z ${ZINIT_ICE[(i)(\!|)(sh|bash|ksh|csh)]} ]] && \
                        {
                            (( !${+ZINIT_ICE[nocompile]} )) && {
                                zcompile "${list[1]}" &>/dev/null || {
                                    print -r "Warning: couldn't compile \`${list[1]}'."
                                }
                            }
                        }
                    fi

                    return $ZINIT[annex-multi-flag:pull-active]
                } else {
                    command mkdir -p "$local_dir/$dirname"

                    if (( !ICE_OPTS[opt_-f,--force] )) {
                        .zinit-get-url-mtime "$url"
                    } else {
                        REPLY=$EPOCHSECONDS
                    }

                    # Returned is: modification time of the remote file.
                    # Thus, EPOCHSECONDS - REPLY is: allowed window for the
                    # local file to be modified in. ms-$secs is: files accessed
                    # within last $secs seconds. Thus, if there's no match, the
                    # local file is out of date.

                    local secs=$(( EPOCHSECONDS - REPLY ))
                    integer skip_dl
                    local -a matched
                    matched=( $local_dir/$dirname/$filename(DNms-$secs) )
                    (( ${#matched} )) && {
                        (( ${+ZINIT_ICE[run-atpull]} )) && skip_dl=1 || return 0
                    }

                    if [[ ! -f $local_dir/$dirname/$filename ]] {
                        ZINIT[annex-multi-flag:pull-active]=2
                    } else {
                        ZINIT[annex-multi-flag:pull-active]=$(( secs > 1 ? (2 - skip_dl) : 3 ))
                    }

                    if (( !skip_dl )) {
                        [[ ${ICE_OPTS[opt_-r,--reset]} = 1 ]] && {
                            [[ ${ICE_OPTS[opt_-q,--quiet]} != 1 && -f $dirname/$filename ]] && print -P "${ZINIT[col-msg2]}Removing the file (-r/--reset given)...%f%b"
                            command rm -f "$dirname/$filename"
                        }
                    }

                    # Run annexes' atpull hooks (the before atpull-ice ones)
                    [[ $update = -u && ${ZINIT_ICE[atpull][1]} = *"!"* ]] && {
                        reply=( "${(@on)ZINIT_EXTS[(I)z-annex hook:\\\!atpull <->]}" )
                        for key in "${reply[@]}"; do
                            arr=( "${(Q)${(z@)ZINIT_EXTS[$key]}[@]}" )
                            "${arr[5]}" snippet "$save_url" "$id_as" "$local_dir/$dirname" \!atpull
                        done
                    }

                    [[ $update = -u && ${ZINIT_ICE[atpull][1]} = *"!"* ]] && .zinit-countdown atpull && { local __oldcd=$PWD; (( ${+ZINIT_ICE[nocd]} == 0 )) && { () { setopt localoptions noautopushd; builtin cd -q "$local_dir/$dirname"; } && .zinit-at-eval "${ZINIT_ICE[atpull]#!}" ${ZINIT_ICE[atclone]}; ((1)); } || .zinit-at-eval "${ZINIT_ICE[atpull]#!}" ${ZINIT_ICE[atclone]}; () { setopt localoptions noautopushd; builtin cd -q "$__oldcd"; };}
                    
                    if (( !skip_dl )) {
                        if { ! .zinit-download-file-stdout "$url" >! "$dirname/$filename" } {
                            if { ! .zinit-download-file-stdout "$url" 1 >! "$dirname/$filename" } {
                                command rm -f "$dirname/$filename"
                                print -r "Download failed. No available download tool? (one of: curl, wget, lftp, lynx)"
                                return 4
                            }
                        }
                    }
                    return $ZINIT[annex-multi-flag:pull-active]
                }
            )
            retval=$?

            # Overestimate the pull-level to 2 also in error situations
            # – no hooks will be run anyway because of the error
            ZINIT[annex-multi-flag:pull-active]=$retval

            if [[ -n ${ZINIT_ICE[compile]} ]]; then
                list=( ${(M)~ZINIT_ICE[compile]##/*}(DN) $local_dir/$dirname/${~ZINIT_ICE[compile]}(DN) )
                [[ ${#list} -eq 0 ]] && {
                    print "Warning: ice compile'' didn't match any files."
                } || {
                    local matched
                    for matched in ${list[@]}; do
                        builtin zcompile "$matched"
                    done
                    ((1))
                }
            fi

            if [[ $ZINIT_ICE[as] != command ]] && (( ${+ZINIT_ICE[svn]} == 0 )); then
                local file_path=$local_dir/$dirname/$filename
                if [[ -n ${ZINIT_ICE[pick]} ]]; then
                    list=( ${(M)~ZINIT_ICE[pick]##/*}(DN) $local_dir/$dirname/${~ZINIT_ICE[pick]}(DN) )
                    file_path=${list[1]}
                fi
                [[ -e $file_path && -z ${ZINIT_ICE[(i)(\!|)(sh|bash|ksh|csh)]} && $file_path != */dev/null ]] && {
                    (( !${+ZINIT_ICE[nocompile]} )) && {
                        zcompile "$file_path" 2>/dev/null || {
                            print -r "Couldn't compile \`${file_path:t}', it MIGHT be wrongly downloaded"
                            print -r "(snippet URL points to a directory instead of a file?"
                            print -r "to download directory, use preceding: zinit ice svn)."
                            retval=2
                        }
                    }
                }
            fi
        } else {
            # File
            [[ ${ICE_OPTS[opt_-r,--reset]} = 1 ]] && {
                [[ ${ICE_OPTS[opt_-q,--quiet]} != 1 && -f $dirname/$filename ]] && print -P "${ZINIT[col-msg2]}Removing the file (-r/--reset given)...%f%b"
                command rm -f "$local_dir/$dirname/$filename"
            }

            # Run annexes' atpull hooks (the before atpull-ice ones)
            [[ $update = -u && ${ZINIT_ICE[atpull][1]} = *"!"* ]] && {
                reply=( "${(@on)ZINIT_EXTS[(I)z-annex hook:\\\!atpull <->]}" )
                for key in "${reply[@]}"; do
                    arr=( "${(Q)${(z@)ZINIT_EXTS[$key]}[@]}" )
                    "${arr[5]}" "snippet" "$save_url" "$id_as" "$local_dir/$dirname" \!atpull
                done
            }

            (( ${+ZINIT_ICE[reset]} )) && (
                (( !ICE_OPTS[opt_-q,--quiet] )) && print -P "%F{220}reset: running ${ZINIT_ICE[reset]:-rm -f $local_dir/$dirname/$filename}%f%b"
                eval "${ZINIT_ICE[reset]:-command rm -f $local_dir/$dirname/$filename}"
            )

            [[ $update = -u && ${ZINIT_ICE[atpull][1]} = *"!"* ]] && .zinit-countdown atpull && { local __oldcd=$PWD; (( ${+ZINIT_ICE[nocd]} == 0 )) && { () { setopt localoptions noautopushd; builtin cd -q "$local_dir/$dirname"; } && .zinit-at-eval "${ZINIT_ICE[atpull]#!}" ${ZINIT_ICE[atclone]}; ((1)); } || .zinit-at-eval "${ZINIT_ICE[atpull]#!}" ${ZINIT_ICE[atclone]}; () { setopt localoptions noautopushd; builtin cd -q "$__oldcd"; };}

            retval=2
            command mkdir -p "$local_dir/$dirname"
            if (( !ICE_OPTS[opt_-q,--quiet] )) && [[ $url != /dev/null ]] {
                print -P "${ZINIT[col-msg1]}Copying ${ZINIT[col-obj]}$filename${ZINIT[col-msg1]}...%f%b"
                command cp -vf "$url" "$local_dir/$dirname/$filename" || \
                    { print -Pr -- "${ZINIT[col-error]}An error occured.%f%b"; retval=4; }
            } else {
                command cp -f "$url" "$local_dir/$dirname/$filename" || \
                    { print -Pr -- "${ZINIT[col-error]}An error occured.%f%b"; retval=4; }
            }
        }

        if [[ ${${:-$local_dir/$dirname}%%/##} != ${ZINIT[SNIPPETS_DIR]} ]] {
            # Store ices at "clone" and update of snippet, SVN and single-file
            local pfx=$local_dir/$dirname/._zinit
            .zinit-store-ices "$pfx" ZINIT_ICE url_rsvd "" "$save_url" "${+ZINIT_ICE[svn]}"
        } elif [[ -n $id_as ]] {
            print -Pr "${ZINIT[col-error]}Warning%f%b: the snippet" \
                "${ZINIT[col-obj]}${(qqq)id_as}%f%b isn't fully downloaded - you should" \
                "remove it with ${ZINIT[col-file]}\`zinit delete ${(qqq)id_as}'%f%b."
        }

        (( retval == 4 )) && { command rmdir "$local_dir/$dirname" 2>/dev/null; return $retval; }

        (( retval == 0 )) && {
            # Run annexes' atpull hooks (the `always' after atpull-ice ones)
            reply=( ${(@on)ZINIT_EXTS[(I)z-annex hook:%atpull <->]} )
            for key in "${reply[@]}"; do
                arr=( "${(Q)${(z@)ZINIT_EXTS[$key]}[@]}" )
                "${arr[5]}" snippet "$save_url" "$id_as" "$local_dir/$dirname" \%atpull
            done

            if [[ -n ${ZINIT_ICE[ps-on-update]} ]]; then
                if (( !ICE_OPTS[opt_-q,--quiet] )) {
                    print -r "Running snippet's provided update code: ${ZINIT[col-info]}${ZINIT_ICE[ps-on-update][1,50]}${ZINIT_ICE[ps-on-update][51]:+…}${ZINIT[col-rst]}"
                    (
                        builtin cd -q "$local_dir/$dirname";
                        eval "${ZINIT_ICE[ps-on-update]}"
                    )
                } else {
                    (
                        builtin cd -q "$local_dir/$dirname";
                        eval "${ZINIT_ICE[ps-on-update]}" &> /dev/null
                    )
                }
            fi
            return 0;
        }

        [[ ${+ZINIT_ICE[make]} = 1 && ${ZINIT_ICE[make]} = "!!"* ]] && .zinit-countdown make && { local make=${ZINIT_ICE[make]}; @zinit-substitute make; command make -C "$local_dir/$dirname" ${(@s; ;)${make#\!\!}}; }

        if [[ -n ${ZINIT_ICE[mv]} ]]; then
            if [[ ${ZINIT_ICE[mv]} = *("->"|"→")* ]] {
                local from=${ZINIT_ICE[mv]%%[[:space:]]#(->|→)*} to=${ZINIT_ICE[mv]##*(->|→)[[:space:]]#} || \
            } else {
                local from=${ZINIT_ICE[mv]%%[[:space:]]##*} to=${ZINIT_ICE[mv]##*[[:space:]]##}
            }
            @zinit-substitute from to
            local -a afr
            ( () { setopt localoptions noautopushd; builtin cd -q "$local_dir/$dirname"; } || return 1
              afr=( ${~from}(DN) )
              if (( ${#afr} )) {
                  if (( !ICE_OPTS[opt_-q,--quiet] )) {
                      command mv -vf "${afr[1]}" "$to"
                      command mv -vf "${afr[1]}".zwc "$to".zwc 2>/dev/null
                  } else {
                      command mv -f "${afr[1]}" "$to"
                      command mv -f "${afr[1]}".zwc "$to".zwc 2>/dev/null
                  }
              }
            )
        fi

        if [[ -n ${ZINIT_ICE[cp]} ]]; then
            if [[ ${ZINIT_ICE[cp]} = *("->"|"→")* ]] {
                local from=${ZINIT_ICE[cp]%%[[:space:]]#(->|→)*} to=${ZINIT_ICE[cp]##*(->|→)[[:space:]]#} || \
            } else {
                local from=${ZINIT_ICE[cp]%%[[:space:]]##*} to=${ZINIT_ICE[cp]##*[[:space:]]##}
            }
            @zinit-substitute from to
            local -a afr
            ( () { setopt localoptions noautopushd; builtin cd -q "$local_dir/$dirname"; } || return 1
              afr=( ${~from}(DN) )
              if (( ${#afr} )) {
                  if (( !ICE_OPTS[opt_-q,--quiet] )) {
                      command cp -vf "${afr[1]}" "$to"
                      command cp -vf "${afr[1]}".zwc "$to".zwc 2>/dev/null
                  } else {
                      command cp -f "${afr[1]}" "$to"
                      command cp -f "${afr[1]}".zwc "$to".zwc 2>/dev/null
                  }
              }
            )
        fi

        [[ ${+ZINIT_ICE[make]} = 1 && ${ZINIT_ICE[make]} = ("!"[^\!]*|"!") ]] && .zinit-countdown make && { local make=${ZINIT_ICE[make]}; @zinit-substitute make; command make -C "$local_dir/$dirname" ${(@s; ;)${make#\!}}; }

        if [[ $update = -u ]] {
            # Run annexes' atpull hooks (the before atpull-ice ones)
            [[ ${ZINIT_ICE[atpull][1]} != *"!"* ]] && {
                reply=( "${(@on)ZINIT_EXTS[(I)z-annex hook:\\\!atpull <->]}" )
                for key in "${reply[@]}"; do
                    arr=( "${(Q)${(z@)ZINIT_EXTS[$key]}[@]}" )
                    "${arr[5]}" "snippet" "$save_url" "$id_as" "$local_dir/$dirname" \!atpull
                done
            }

            [[ -n ${ZINIT_ICE[atpull]} && ${ZINIT_ICE[atpull][1]} != *"!"* ]] && .zinit-countdown atpull && { local __oldcd=$PWD; (( ${+ZINIT_ICE[nocd]} == 0 )) && { () { setopt localoptions noautopushd; builtin cd -q "$local_dir/$dirname"; } && .zinit-at-eval "${ZINIT_ICE[atpull]#!}" ${ZINIT_ICE[atclone]}; ((1)); } || .zinit-at-eval "${ZINIT_ICE[atpull]#!}" ${ZINIT_ICE[atclone]}; () { setopt localoptions noautopushd; builtin cd -q "$__oldcd"; };}
        } else {
            # Run annexes' atclone hooks (the before atclone-ice ones)
            reply=( "${(@on)ZINIT_EXTS[(I)z-annex hook:\\\!atclone <->]}" )
            for key in "${reply[@]}"; do
                arr=( "${(Q)${(z@)ZINIT_EXTS[$key]}[@]}" )
                "${arr[5]}" snippet "$save_url" "$id_as" "$local_dir/$dirname" \!atclone
            done

            local atclone=${ZINIT_ICE[atclone]} extract=${ZINIT_ICE[extract]}
            @zinit-substitute atclone extract

            [[ -n $atclone ]] && .zinit-countdown atclone && { local __oldcd=$PWD; (( ${+ZINIT_ICE[nocd]} == 0 )) && { () { setopt localoptions noautopushd; builtin cd -q "$local_dir/$dirname"; } && eval "$atclone"; ((1)); } || eval "$atclone"; () { setopt localoptions noautopushd; builtin cd -q "$__oldcd"; }; }

            if (( ${+ZINIT_ICE[extract]} )) {
                .zinit-extract snippet "$extract" "$local_dir/$dirname"
            }

            # Run annexes' atclone hooks (the after atclone-ice ones)
            reply=( "${(@on)ZINIT_EXTS[(I)z-annex hook:atclone <->]}" )
            for key in "${reply[@]}"; do
                arr=( "${(Q)${(z@)ZINIT_EXTS[$key]}[@]}" )
                "${arr[5]}" snippet "$save_url" "$id_as" "$local_dir/$dirname" atclone
            done
        }

        [[ ${+ZINIT_ICE[make]} = 1 && ${ZINIT_ICE[make]} != "!"* ]] && .zinit-countdown make && { local make=${ZINIT_ICE[make]}; @zinit-substitute make; command make -C "$local_dir/$dirname" ${(@s; ;)make}; }

        # Run annexes' atpull hooks (the after atpull-ice ones)
        [[ $update = -u ]] && {
            reply=( "${(@on)ZINIT_EXTS[(I)z-annex hook:atpull <->]}" )
            for key in "${reply[@]}"; do
                arr=( "${(Q)${(z@)ZINIT_EXTS[$key]}[@]}" )
                "${arr[5]}" snippet "$save_url" "$id_as" "$local_dir/$dirname" atpull
            done

            if (( ZINIT[annex-multi-flag:pull-active] > 0 && ${+ZINIT_ICE[extract]} )) {
                local extract=${ZINIT_ICE[extract]}
                [[ -n $extract ]] && @zinit-substitute extract
                .zinit-extract snippet "$extract" "$local_dir/$dirname"
            }

            # Run annexes' atpull hooks (the `always' after atpull-ice ones)
            reply=( ${(@on)ZINIT_EXTS[(I)z-annex hook:%atpull <->]} )
            for key in "${reply[@]}"; do
                arr=( "${(Q)${(z@)ZINIT_EXTS[$key]}[@]}" )
                "${arr[5]}" snippet "$save_url" "$id_as" "$local_dir/$dirname" \%atpull
            done

            if [[ -n ${ZINIT_ICE[ps-on-update]} ]]; then
                if (( !ICE_OPTS[opt_-q,--quiet] )) {
                    print -r "Running snippet's provided update code: ${ZINIT[col-info]}${ZINIT_ICE[ps-on-update][1,50]}${ZINIT_ICE[ps-on-update][51]:+…}${ZINIT[col-rst]}"
                }
                eval "${ZINIT_ICE[ps-on-update]}"
            fi
        }
        ((1))
    ) || return $?

    typeset -ga INSTALLED_EXECS
    { INSTALLED_EXECS=( "${(@f)$(</tmp/zinit-execs.$$.lst)}" ) } 2>/dev/null
    command rm -f /tmp/zinit-execs.$$.lst

    # After additional executions like atclone'' - install completions (2 - snippets)
    local -A ICE_OPTS
    ICE_OPTS[opt_-q,--quiet]=1
    [[ 1 = ${+ZINIT_ICE[nocompletions]} || ${ZINIT_ICE[as]} = null ]] || \
        .zinit-install-completions "%" "$local_dir/$dirname" 0

    return $retval
}
# ]]]
# FUNCTION: .zinit-update-snippet [[[
.zinit-update-snippet() {
    emulate -LR zsh
    setopt extendedglob warncreateglobal typesetsilent noshortloops rcquotes

    local -a tmp opts
    local url=$1
    integer correct=0
    [[ -o ksharrays ]] && correct=1
    opts=( -u ) # for z-a-as-monitor

    # Create a local copy of ICE_OPTS, basically
    # for z-a-as-monitor annex
    local -A ice_opts
    ice_opts=( "${(kv)ICE_OPTS[@]}" )
    local -A ICE_OPTS
    ICE_OPTS=( "${(kv)ice_opts[@]}" )

    command rm -f /tmp/zinit-execs.$$.lst

    ZINIT[annex-multi-flag:pull-active]=0

    # Remove leading whitespace and trailing /
    url=${${url#${url%%[! $'\t']*}}%/}
    ZINIT_ICE[teleid]=${ZINIT_ICE[teleid]:-$url}
    [[ ${ZINIT_ICE[as]} = null ]] && \
        ZINIT_ICE[pick]=${ZINIT_ICE[pick]:-/dev/null}

    local local_dir dirname filename save_url=$url \
        id_as=${ZINIT_ICE[id-as]:-$url}

    .zinit-pack-ice "$id_as" ""

    # Allow things like $OSTYPE in the URL
    eval "url=\"$url\""

    # - case A: called from `update --all', ZINIT_ICE empty, static ice will win
    # - case B: called from `update', ZINIT_ICE packed, so it will win
    tmp=( "${(Q@)${(z@)ZINIT_SICE[$id_as]}}" )
    (( ${#tmp} > 1 && ${#tmp} % 2 == 0 )) && \
        ZINIT_ICE=( "${(kv)ZINIT_ICE[@]}" "${tmp[@]}" ) || \
        { [[ -n ${ZINIT_SICE[$id_as]} ]] && \
            print -Pr "${ZINIT[col-error]}WARNING:${ZINIT[col-msg2]} Inconsistency #3" \
            "occurred, please report the string:" \
            "\`${ZINIT[col-obj]}${ZINIT_SICE[$id_as]}${ZINIT[col-msg2]}'" \
            "on GitHub issues page: https://github.com/zdharma/zinit/issues/%f%b"
        }
    id_as=${ZINIT_ICE[id-as]:-$id_as}

    # Oh-My-Zsh, Prezto and manual shorthands
    (( ${+ZINIT_ICE[svn]} )) && {
        [[ $url = *(OMZ::|robbyrussell*oh-my-zsh|ohmyzsh/ohmyzsh)* ]] && local ZSH=${ZINIT[SNIPPETS_DIR]}
        url[1-correct,5-correct]=${ZINIT_1MAP[${url[1-correct,5-correct]}]:-${url[1-correct,5-correct]}}
    } || {
        url[1-correct,5-correct]=${ZINIT_2MAP[${url[1-correct,5-correct]}]:-${url[1-correct,5-correct]}}
    }

    .zinit-get-object-path snippet "$id_as" || \
        { print -P "$ZINIT[col-msg2]Error: the snippet" \
            "\`$ZINIT[col-obj]$id_as$ZINIT[col-msg2]'" \
            "doesn't exist, aborting the update.%f%b"
          return 1
        }
    filename=$reply[-2] dirname=$reply[-2] local_dir=$reply[-3]

    local -a arr
    local key
    reply=( "${(@on)ZINIT_EXTS[(I)z-annex hook:preinit <->]}" )
    for key in "${reply[@]}"; do
        arr=( "${(Q)${(z@)ZINIT_EXTS[$key]}[@]}" )
        "${arr[5]}" snippet "$save_url" "$id_as" "$local_dir/$dirname" u-preinit || \
            return $(( 10 - $? ))
    done

    # Download or copy the file
    [[ $url = *github.com* && $url != */raw/* ]] && url=${url/\/(blob|tree)\///raw/}
    .zinit-download-snippet "$save_url" "$url" "$id_as" "$local_dir" "$dirname" "$filename" "-u"

    typeset -ga INSTALLED_EXECS
    { INSTALLED_EXECS=( "${(@f)$(</tmp/zinit-execs.$$.lst)}" ) } 2>/dev/null
    command rm -f /tmp/zinit-execs.$$.lst

    return $?
}
# ]]]
# FUNCTION: .zinit-get-latest-gh-r-url-part [[[
# Gets version string of latest release of given Github
# package. Connects to Github releases page.
.zinit-get-latest-gh-r-url-part() {
    emulate -LR zsh
    setopt extendedglob warncreateglobal typesetsilent noshortloops

    REPLY=
    local user=$1 plugin=$2 urlpart=$3

    if [[ -z $urlpart ]] {
        local url=https://github.com/$user/$plugin/releases/$ZINIT_ICE[ver]
    } else {
        local url=https://$urlpart
    }

    local -A matchstr
    matchstr=(
        i386    "(386|686)"
        i686    "(386|686)"
        x86_64  "(x86_64|amd64|intel)"
        amd64   "(x86_64|amd64|intel)"
        aarch64 "aarch64"
        linux   "(linux|linux-gnu)"
        darwin  "(darwin|macos|mac-os|osx|os-x)"
        cygwin  "(windows|cygwin)"
        windows "(windows|cygwin)"
    )

    local -a list list2
    list=( ${(@f)"$( { .zinit-download-file-stdout $url || .zinit-download-file-stdout $url 1; } 2>/dev/null | \
                  command grep -o 'href=./'$user'/'$plugin'/releases/download/[^"]\+')"} )
    list=( ${list[@]#href=?} )

    [[ -n $ZINIT_ICE[bpick] ]] && list=( ${(M)list[@]:#(#i)*/$~ZINIT_ICE[bpick]} )

    [[ ${#list} -gt 1 ]] && {
        list2=( ${(M)list[@]:#(#i)*${~matchstr[$CPUTYPE]:-${CPUTYPE#(#i)(i|amd)}}*} )
        [[ ${#list2} -gt 0 ]] && list=( ${list2[@]} )
    }

    [[ ${#list} -gt 1 ]] && {
        list2=( ${(M)list[@]:#(#i)*${~matchstr[${${OSTYPE%(#i)-gnu}%%(-|)[0-9.]##}]:-${${OSTYPE%(#i)-gnu}%%(-|)[0-9.]##}}*} )
        [[ ${#list2} -gt 0 ]] && list=( ${list2[@]} )
    }

    [[ ${#list} -gt 1 ]] && {
        list2=( ${list[@]:#(#i)*.sha[[:digit:]]#} )
        [[ ${#list2} -gt 0 ]] && list=( ${list2[@]} )
    }

    [[ $#list -eq 0 ]] && {
        print -nr "${ZINIT[col-msg2]}Didn't find correct Github" \
            "release-file to download"
        if [[ -n $ZINIT_ICE[bpick] ]] {
            print -nr ", try adapting" \
                "${ZINIT[col-obj]}bpick${ZINIT[col-msg2]}-ICE" \
                "(currently it is:${ZINIT[col-file]}" \
                "$ZINIT_ICE[bpick]${ZINIT[col-msg2]})."
        } else {
            print -n .
        }
        print -P "%f%b"
        return 1
    }

    REPLY=$list[1]

    [[ -n $REPLY ]] # testable
}
# ]]]
# FUNCTION: ziextract [[[
# If the file is an archive, it is extracted by this function.
# Next stage is scanning of files with the common utility `file',
# to detect executables. They are given +x mode. There are also
# messages to the user on performed actions.
#
# $1 - url
# $2 - file
ziextract() {
    emulate -LR zsh
    setopt extendedglob typesetsilent noshortloops # warncreateglobal

    local -a opt_move opt_norm opt_auto opt_nobkp
    zparseopts -D -E -move=opt_move -norm=opt_norm \
            -auto=opt_auto -nobkp=opt_nobkp || \
        { print -P -r -- "%F{160}Incorrect options given to \`ziextract' (available are: %F{221}--auto%F{160},%F{221}--move%F{160},%F{221}--norm%F{160},%F{221}--nobkp%F{160}).%f%b"; return 1; }

    local file="$1" ext="$2"
    integer move=${${${(M)${#opt_move}:#0}:+0}:-1} \
            norm=${${${(M)${#opt_norm}:#0}:+0}:-1} \
            auto=${${${(M)${#opt_auto}:#0}:+0}:-1} \
            nobkp=${${${(M)${#opt_nobkp}:#0}:+0}:-1}

    if (( auto )) {
        # First try known file extensions
        local -a files
        integer ret_val
        files=( (#i)**/*.(zip|rar|7z|tgz|tbz2|tar.gz|tar.bz2|tar.7z|txz|tar.xz|gz|xz|tar|dmg)~(*/*|.(_backup|git))/*(-.DN) )
        for file ( $files ) {
            ziextract "$file" $opt_move $opt_norm $opt_nobkp ${${${#files}:#1}:+--nobkp}
            ret_val+=$?
        }
        # Second, try to find the archive via `file' tool
        if (( !${#files} )) {
            local -aU output infiles stage2_processed archives
            infiles=( **/*~(._zinit|.zinit_lastupd|._backup|.git)(|/*)~*/*/*(-.DN) )
            output=( ${(@f)"$(command file -- $infiles 2>&1)"} )
            archives=( ${(M)output[@]:#(#i)(* |(#s))(zip|rar|xz|7-zip|gzip|bzip2|tar) *} )
            for file ( $archives ) {
                local fname=${(M)file#(${(~j:|:)infiles}): } desc=${file#(${(~j:|:)infiles}): } type
                fname=${fname%%??}
                [[ -z $fname || -n ${stage2_processed[(r)$fname]} ]] && continue
                type=${(L)desc/(#b)(#i)(* |(#s))(zip|rar|xz|7-zip|gzip|bzip2|tar) */$match[2]}
                if [[ $type = (zip|rar|xz|7-zip|gzip|bzip2|tar) ]] {
                    (( !ICE_OPTS[opt_-q,--quiet] )) && \
                        print -Pr -- "$ZINIT[col-pre]ziextract:$ZINIT[col-info2]" \
                            "Note:%f%b" \
                            "detected a $ZINIT[col-obj]$type%f%b" \
                            "archive in the file $ZINIT[col-file]$fname%f%b."
                    ziextract "$fname" "$type" $opt_move $opt_norm --norm ${${${#archives}:#1}:+--nobkp}
                    integer iret_val=$?
                    ret_val+=iret_val

                    (( iret_val )) && continue

                    # Support nested tar.(bz2|gz|…) archives
                    local infname=$fname
                    [[ -f $fname.out ]] && fname=$fname.out
                    files=( *.tar(ND) )
                    if [[ -f $fname || -f ${fname:r} ]] {
                        local -aU output2 archives2
                        output2=( ${(@f)"$(command file -- "$fname"(N) "${fname:r}"(N) $files[1](N) 2>&1)"} )
                        archives2=( ${(M)output2[@]:#(#i)(* |(#s))(zip|rar|xz|7-zip|gzip|bzip2|tar) *} )
                        local file2
                        for file2 ( $archives2 ) {
                            fname=${file2%:*} desc=${file2##*:}
                            local type2=${(L)desc/(#b)(#i)(* |(#s))(zip|rar|xz|7-zip|gzip|bzip2|tar) */$match[2]}
                            if [[ $type != $type2 && \
                                $type2 = (zip|rar|xz|7-zip|gzip|bzip2|tar)
                            ]] {
                                # TODO: if multiple archives are really in the archive,
                                # this might delete too soon… However, it's unusual case.
                                [[ $fname != $infname && $norm -eq 0 ]] && command rm -f "$infname"
                                (( !ICE_OPTS[opt_-q,--quiet] )) && \
                                    print -Pr -- "$ZINIT[col-pre]ziextract:$ZINIT[col-info2]" \
                                        "Note:%f%b" \
                                        "detected a $ZINIT[col-obj]$type2%f%b" \
                                        "archive in the file $ZINIT[col-file]$fname%f%b."
                                ziextract "$fname" "$type2" $opt_move $opt_norm ${${${#archives}:#1}:+--nobkp}
                                ret_val+=$?
                                stage2_processed+=( $fname )
                                if [[ $fname == *.out ]] {
                                    [[ -f $fname ]] && command mv -f "$fname" "${fname%.out}"
                                    stage2_processed+=( ${fname%.out} )
                                }
                            }
                        }
                    }
                }
            }
        }
        return $ret_val
    }

    if [[ -z $file ]] {
        print -Pr -- "$ZINIT[col-pre]ziextract:%f%b" \
            "$ZINIT[col-error]ERROR:$ZINIT[col-msg2]" \
            "argument needed (the file to extract) or" \
            "the --auto option"
        return 1
    }
    if [[ ! -e $file ]] {
        print -Pr -- "$ZINIT[col-pre]ziextract:%f%b" \
            "$ZINIT[col-error]ERROR:$ZINIT[col-msg2]" \
            "the file \`$ZINIT[col-obj]$file$ZINIT[col-msg2]'" \
            "doesn't exist, aborting the extraction."
        return 1
    }
    if (( !nobkp )) {
        command mkdir -p ._backup
        command rm -rf ._backup/*(DN)
        command mv -f *~(._zinit*|.zinit_lastupd|._backup|.git|.svn|.hg|$file)(DN) ._backup 2>/dev/null
    }

    .zinit-extract-wrapper() {
        local file="$1" fun="$2" retval
        (( !ICE_OPTS[opt_-q,--quiet] )) && \
            print -Pr "$ZINIT[col-pre]ziextract:$ZINIT[col-msg1] Unpacking the files from:" \
                "\`$ZINIT[col-obj]$file$ZINIT[col-msg1]'...%f%b"
        $fun; retval=$?
        (( retval == 0 )) && {
            local -a files
            files=( *~(._zinit*|.zinit_lastupd|._backup|.git|.svn|.hg|$file)(DN) )
            (( ${#files} && !norm )) && command rm -f "$file"
        }
        return $retval
    }

    →zinit-check() { (( ${+commands[$1]} )) || \
        print -Pr "$ZINIT[col-error]Error:%f%b No command $ZINIT[col-obj]$1%f%b," \
            "it is required to unpack $ZINIT[col-file]$2%f%b."
    }

    case "${${ext:+.$ext}:-$file}" in
        ((#i)*.zip)
            →zinit-extract() { →zinit-check unzip "$file"; command unzip -o "$file"; }
            ;;
        ((#i)*.rar)
            →zinit-extract() { →zinit-check unrar "$file"; command unrar x "$file"; }
            ;;
        ((#i)*.tar.bz2|(#i)*.tbz2)
            →zinit-extract() { →zinit-check bzip2 "$file"; command bzip2 -dc "$file" | command tar -xf -; }
            ;;
        ((#i)*.tar.gz|(#i)*.tgz)
            →zinit-extract() { →zinit-check gzip "$file"; command gzip -dc "$file" | command tar -xf -; }
            ;;
        ((#i)*.tar.xz|(#i)*.txz)
            →zinit-extract() { →zinit-check xz "$file"; command xz -dc "$file" | command tar -xf -; }
            ;;
        ((#i)*.tar.7z|(#i)*.t7z)
            →zinit-extract() { →zinit-check 7z "$file"; command 7z x -so "$file" | command tar -xf -; }
            ;;
        ((#i)*.tar)
            →zinit-extract() { →zinit-check tar "$file"; command tar -xf "$file"; }
            ;;
        ((#i)*.gz|(#i)*.gzip)
            if [[ $file != (#i)*.gz ]] {
                command mv $file $file.gz
                file=$file.gz
            }
            →zinit-extract() { →zinit-check gunzip "$file"; command gunzip "$file" |& command egrep -v '.out$'; return $pipestatus[1]; }
            ;;
        ((#i)*.bz2|(#i)*.bzip2)
            →zinit-extract() { →zinit-check bunzip2 "$file"; command bunzip2 "$file" |& command egrep -v '.out$'; return $pipestatus[1];}
            ;;
        ((#i)*.xz)
            if [[ $file != (#i)*.xz ]] {
                command mv $file $file.xz
                file=$file.xz
            }
            →zinit-extract() { →zinit-check xz "$file"; command xz -d "$file"; }
            ;;
        ((#i)*.7z|(#i)*.7-zip)
            →zinit-extract() { →zinit-check 7z "$file"; command 7z x "$file" >/dev/null;  }
            ;;
        ((#i)*.dmg)
            →zinit-extract() {
                local prog
                for prog ( hdiutil cp ) { →zinit-check $prog "$file"; }

                integer retval
                local attached_vol="$( command hdiutil attach "$file" | \
                           command tail -n1 | command cut -f 3 )"

                command cp -Rf $attached_vol/*(D) .
                retval=$?
                command hdiutil detach $attached_vol

                (( retval )) && {
                    print -Pr -- "$ZINIT[col-pre]ziextract:" \
                            "$ZINIT[col-error]Warning:$ZINIT[col-msg1]" \
                            "problem occurred when attempted to copy the files" \
                            "from the mounted image:" \
                            "\`$ZINIT[col-obj]$file$ZINIT[col-msg1]'.%f%b"
                }
                return $retval
            }
            ;;
        ((#i)*.deb)
            →zinit-extract() { →zinit-check dpkg-deb "$file"; command dpkg-deb -R "$file" .; }
            ;;
    esac

    if [[ $(typeset -f + -- →zinit-extract) == "→zinit-extract" ]] {
        .zinit-extract-wrapper "$file" →zinit-extract || {
            local -a bfiles
            bfiles=( ._backup/*(DN) )
            if (( ${#bfiles} )) {
                print -nPr -- "$ZINIT[col-pre]ziextract:" \
                    "$ZINIT[col-error]WARNING:$ZINIT[col-msg1]" \
                    "extraction of archive had problems"
                if (( !nobkp )) {
                    print ", restoring previous" \
                        "version of the plugin/snippet.%f%b"
                    command mv ._backup/*(DN) . 2>/dev/null
                } else {
                    print -P ".%f%b"
                }
            } else {
                print -Pr -- "$ZINIT[col-pre]ziextract:" \
                    "$ZINIT[col-error]WARNING:$ZINIT[col-msg1]" \
                    "extraction of the archive" \
                    "\`$ZINIT[col-obj]$file$ZINIT[col-msg1]' had problems.%f%b"
            }
            unfunction -- →zinit-extract →zinit-check 2>/dev/null
            return 1
        }
        unfunction -- →zinit-extract →zinit-check
    } else {
        integer warning=1
    }
    unfunction -- .zinit-extract-wrapper

    local -a execs
    execs=( **/*~(._zinit(|/*)|.git(|/*)|.svn(|/*)|.hg(|/*)|._backup(|/*))(DN-.) )
    [[ ${#execs} -gt 0 && -n $execs ]] && {
        execs=( ${(@f)"$( file ${execs[@]} )"} )
        execs=( "${(M)execs[@]:#[^:]##:*executable*}" )
        execs=( "${execs[@]/(#b)([^:]##):*/${match[1]}}" )
    }

    print -rl -- ${execs[@]} >! /tmp/zinit-execs.$$.lst
    if [[ ${#execs} -gt 0 ]] {
        command chmod a+x "${execs[@]}"
        if (( !ICE_OPTS[opt_-q,--quiet] )) {
            if (( ${#execs} == 1 )); then
                    print -Pr -- "$ZINIT[col-pre]ziextract:%f%b" \
                        "Successfully extracted and assigned +x chmod to the file:" \
                        "\`$ZINIT[col-obj]${execs[1]}%f%b'."
            else
                local sep="$ZINIT[col-rst],$ZINIT[col-obj] "
                if (( ${#execs} > 7 )) {
                    print -Pr -- "$ZINIT[col-pre]ziextract:%f%b Successfully" \
                        "extracted and marked executable the appropriate files" \
                        "($ZINIT[col-obj]${(pj:$sep:)${(@)execs[1,5]:t}},…%f%b) contained" \
                        "in \`$ZINIT[col-file]$file%f%b'. All the extracted" \
                        "$ZINIT[col-obj]${#execs}%f%b executables are" \
                        "available in the $ZINIT[col-msg2]INSTALLED_EXECS%f%b" \
                        "array."
                } else {
                    print -Pr -- "$ZINIT[col-pre]ziextract:%f%b Successfully" \
                        "extracted and marked executable the appropriate files" \
                        "($ZINIT[col-obj]${(pj:$sep:)${execs[@]:t}}%f%b) contained" \
                        "in \`$ZINIT[col-file]$file%f%b'."
                }
            fi
        }
    } elif (( warning )) {
        print -Pr -- "$ZINIT[col-pre]ziextract:" \
            "$ZINIT[col-error]WARNING: $ZINIT[col-msg1]didn't recognize the archive" \
            "type of \`$ZINIT[col-obj]$file$ZINIT[col-msg1]'" \
            "${ext:+$ZINIT[col-obj2]/ $ext$ZINIT[col-msg1] }"\
"(no extraction has been done).%f%b"
    }

    (( move )) && {
        local -a files
        files=( *~(._zinit|.git|._backup|.tmp231ABC)(DN/) )
        if (( ${#files} )) {
            if (( ${#files} > 1 )) {
                # TODO: make this unusual situation have more chance of working
                command mkdir -p .tmp231ABC
            }
            [[ -e ''(._zinit|.git|._backup|.tmp231ABC)(#qDN.-[1]) ]] && \
                command mv -f *~(._zinit|.git|._backup|.tmp231ABC)(DN.-) .tmp231ABC
            command mv -f **/*~(*/*/*|^*/*|._zinit(|/*)|.git(|/*)|._backup(|/*))(DN) .
            [[ -d .tmp231ABC ]] && command rmdir .tmp231ABC
        }
        REPLY="${${execs[1]:h}:h}/${execs[1]:t}"
    } || {
        REPLY="${execs[1]}"
    }
    return 0
}
# ]]]
# FUNCTION: .zinit-extract() [[[
.zinit-extract() {
    emulate -LR zsh
    setopt extendedglob warncreateglobal typesetsilent
    local tpe=$1 extract=$2 local_dir=$3
    (
        builtin cd -q "$local_dir" || \
            { print -P -- "${ZINIT[col-error]}ERROR:${ZINIT[col-msg2]} The path" \
                "of the $tpe (\`${ZINIT[col-file]}$local_dir${ZINIT[col-msg2]}')" \
                "isn't accessible.%f%b"
                return 1
            }
        local -a files
        files=( ${(@)${(@s: :)${extract##(\!-|-\!|\!|-)}}// / }(-.DN) )
        [[ ${#files} -eq 0 && -n ${extract##(\!-|-\!|\!|-)} ]] && {
                print -P -- "${ZINIT[col-error]}ERROR:${ZINIT[col-msg2]} The" \
                    "files (\`${ZINIT[col-file]}${extract##(\!-|-\!|\!|-)}${ZINIT[col-msg2]}')" \
                    "not found, cannot extract.%f%b"
                return 1
        } || { (( !${#files} )) && files=( "" ); }
        local file
        for file ( "${files[@]}" ) {
            [[ -z $extract ]] && local auto2=--auto
            ziextract ${${(M)extract:#(\!|-)##}:+--auto} \
                $auto2 $file \
                ${${(MS)extract[1,2]##-}:+--norm} \
                ${${(MS)extract[1,2]##\!}:+--move} \
                ${${${#files}:#1}:+--nobkp}
        }
    )
}
# ]]]
# FUNCTION: zpextract [[[
zpextract() { ziextract "$@"; }
# ]]]
# FUNCTION: .zinit-at-eval [[[
.zinit-at-eval() {
    local atclone="$2" atpull="$1"
    integer retval
    @zinit-substitute atclone atpull
    [[ $atpull = "%atclone" ]] && { eval "$atclone"; retval=$?; } || { eval "$atpull"; retval=$?; }
    return $retval
}
# ]]]

# vim:ft=zsh:sw=4:sts=4:et:foldmarker=[[[,]]]
