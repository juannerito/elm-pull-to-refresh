module PullToRefresh
    exposing
        ( Model
        , Config
        , Msg
        , view
        , init
        , update
        , config
        , canPullToRefresh
        , withMaxDistance
        , withTriggerDistance
        , withPullContent
        , withReleaseContent
        , withLoadingContent
        , stopLoading
        , withAnimationEasingFunc
        , withAnimationDuration
        , subscriptions
        , withRefreshCmd
        )

{-| Pull to refresh behavior in `Elm`.

You define a `Cmd` to be executed as soon as the screen is released after pulling it.

This is working with mouse of touches.

# Types

@docs Model, Config, Msg

# Use

@docs init, update, view, subscriptions, canPullToRefresh, stopLoading

# Config

@docs config, withMaxDistance, withTriggerDistance, withPullContent, withReleaseContent, withLoadingContent, withAnimationEasingFunc, withAnimationDuration, withRefreshCmd
-}

import Internal.PullToRefresh as Internal
import Html exposing (Html, div, text)
import Html.Attributes as Attributes exposing (style)
import Html.Events as Events
import Dom.Scroll
import Task
import Json.Decode as JD
import Touch
import Time exposing (Time, second, millisecond)
import AnimationFrame
import Ease exposing (Easing)


{-| Model to keep in your module's state
-}
type Model
    = Model Internal.Model


{-| Config object to use with this module
-}
type Config msg
    = Config (Internal.Config msg)


{-| Messages to delegate to this module
-}
type Msg
    = NoOp ()
    | OnScroll Float
    | OnDown Internal.Position
    | OnUp Internal.Position
    | OnMove Internal.Position
    | OnReset ()
    | OnUpdateFrame Time


{-| Creates a new simple configuration for this module.

You must give your pull to refresh module a unique id.
This id will be added to the pull to refresh view.


    config "ptr"

-}
config : String -> Config msg
config id =
    Config
        { id = id
        , maxDist = 100
        , triggerDist = 40
        , pullContent = defaultPullContent
        , releaseContent = defaultReleaseContent
        , loadingContent = defaultLoadingContent
        , animationEasingFunc = Ease.inOutQuad
        , animationDuration = 150 * millisecond
        , refreshCmd = Cmd.none
        }


{-| Sets the maximum distance of the pulled content from the top of the screen

    config "ptr" |> withMaxDistance 100

-}
withMaxDistance : Float -> Config msg -> Config msg
withMaxDistance maxDist (Config config) =
    Config { config | maxDist = maxDist }


{-| Sets distance the module will start calling your refresh `Cmd` when you release your click.
This is usally set to something like half the maximum distance

    config "ptr" |> withMaxDistance 100 |> withTriggerDistance 40

-}
withTriggerDistance : Float -> Config msg -> Config msg
withTriggerDistance triggerDist (Config config) =
    Config { config | triggerDist = triggerDist }


{-| Content to be displayed when you are pulling the view but the distance does not exceed the trigger distance yet.

    config "ptr" |> withPullContent (div [] [ text "Pull to refresh" ])

-}
withPullContent : Html msg -> Config msg -> Config msg
withPullContent pullContent (Config config) =
    Config { config | pullContent = pullContent }


{-| Content to be displayed when you are pulling the view and the distance exceeds the trigger distance.
This means that when you'll release the click, your refresh `Cmd` will be executed

    config "ptr" |> withReleaseContent (div [] [ text "Release to refresh" ])

-}
withReleaseContent : Html msg -> Config msg -> Config msg
withReleaseContent releaseContent (Config config) =
    Config { config | releaseContent = releaseContent }


{-| Content to be displayed when refreshing is in progress

    config "ptr" |> withLoadingContent (div [] [ text "Loading ..." ])

-}
withLoadingContent : Html msg -> Config msg -> Config msg
withLoadingContent loadingContent (Config config) =
    Config { config | loadingContent = loadingContent }


{-| Sets duration of animation when the pulled view is returning back to its initial position

    config "ptr" |> withAnimationDuration (150 * millisecond)

-}
withAnimationDuration : Time -> Config msg -> Config msg
withAnimationDuration animationDuration (Config config) =
    Config { config | animationDuration = animationDuration }


{-| Sets the easing function to use for the transition when the pulled view will return back to its initial position

    config "ptr" |> withAnimationEasingFunc inOutQuad

-}
withAnimationEasingFunc : Easing -> Config msg -> Config msg
withAnimationEasingFunc animationEasingFunc (Config config) =
    Config { config | animationEasingFunc = animationEasingFunc }


{-| Sets your `Cmd` to execute to refresh your content

    config "ptr" |> withRefreshCmd executeRequest

-}
withRefreshCmd : Cmd msg -> Config msg -> Config msg
withRefreshCmd refreshCmd (Config config) =
    Config { config | refreshCmd = refreshCmd }


{-| Initializes the module.
You must pass it a `Config` object

    config : Config Msg
    config =
        Ptr.config "ptr"

    Ptr.init config

-}
init : Config msg -> ( Model, Cmd Msg )
init (Config config) =
    ( Model (Internal.initModel config)
    , Dom.Scroll.y config.id
        |> Task.onError (Debug.log "Scroll position error" >> always (Task.succeed 0))
        |> Task.perform OnScroll
    )


{-| Update function to call when you receive messages for this module

    config : Config Msg
    config =
        Ptr.config "ptr"

    update : Msg -> Model -> ( Model, Cmd Msg )
    update msg model =
        case msg of
            PtrMsg msg_ ->
                let
                    ( ptr, cmd ) =
                        Ptr.update PtrMsg msg_ config model.ptr
                in
                    ( { model | ptr = ptr }, cmd )

-}
update : (Msg -> msg) -> Msg -> Config msg -> Model -> ( Model, Cmd msg )
update mapper msg (Config config) (Model model) =
    case msg of
        OnScroll scrollY ->
            ( Model { model | currScrollY = scrollY }, Cmd.none )

        OnDown pos ->
            ( Model { model | state = Internal.start pos model.state }, Cmd.none )

        OnUp pos ->
            if (Internal.getContentTopPosition config model.state) >= config.triggerDist then
                ( Model { model | state = Internal.end config.maxDist pos model.state, loading = True }
                , config.refreshCmd
                )
            else
                ( Model { model | state = Internal.reset config.triggerDist config.maxDist model.state }, Cmd.none )

        OnMove pos ->
            let
                newState =
                    Internal.move pos model.state
            in
                ( Model { model | state = newState }, Cmd.none )

        OnReset () ->
            ( Model { model | loading = False, state = Internal.reset config.triggerDist config.maxDist model.state }, Cmd.none )

        NoOp () ->
            ( Model model, Cmd.none )

        OnUpdateFrame diff ->
            ( Model { model | state = Internal.updateAnim config.animationDuration diff model.state }, Cmd.none )


{-| View that displays your content and handles the pull to refresh behavior.

    config : Config Msg
    config =
        Ptr.config "ptr"

    view : Model -> Html Msg
    view model =
        div
            [ style
                [ ( "border", "1px solid #000" )
                , ( "margin", "auto" )
                , ( "height", "500px" )
                , ( "width", "300px" )
                , ( "position", "relative" )
                ]
            ]
            [ Ptr.view PtrMsg
                config
                model.ptr
                []
                [ div
                    []
                    [ content ]
                ]
            ]

-}
view : (Msg -> msg) -> Config msg -> Model -> List (Html.Attribute msg) -> List (Html msg) -> Html msg
view mapper (Config config) (Model model) attrs content =
    let
        yPos =
            Internal.getContentTopPosition config model.state
    in
        div
            [ style
                [ ( "position", "absolute" )
                , ( "margin", "0" )
                , ( "padding", "0" )
                , ( "overflow", "hidden" )
                , ( "left", "0" )
                , ( "top", "0" )
                , ( "bottom", "0" )
                , ( "right", "0" )
                ]
            ]
            [ viewPullContent mapper (Config config) (Model model) yPos
            , div
                (attrs
                    ++ [ style
                            ([ ( "position", "absolute" )
                             , ( "margin", "0" )
                             , ( "padding", "0" )
                             , ( "overflow", "auto" )
                             , ( "left", "0" )
                             , ( "top", (toString yPos) ++ "px" )
                             , ( "bottom", "0" )
                             , ( "right", "0" )
                             ]
                            )
                       , Attributes.id config.id
                       , Attributes.map mapper <| Events.on "scroll" (JD.map OnScroll Internal.decodeScrollPos)
                       ]
                    ++ (if canPullToRefresh (Model model) then
                            addPullToRefreshAttributes mapper (Model model)
                        else
                            []
                       )
                )
                content
            ]


{-| Returns `True` if the view is pullable, `False` if it's not.

It's actually not pullable if the inner content has a scrollbar and this scrollbar is not at its top position
-}
canPullToRefresh : Model -> Bool
canPullToRefresh (Model { currScrollY }) =
    currScrollY == 0


{-| You must call this function has soon has your refresh `Cmd` is finished executing so that the pull to refresh can be stopped

    stopLoading PtrMsg

-}
stopLoading : (Msg -> msg) -> Cmd msg
stopLoading mapper =
    Cmd.map mapper <| Task.perform OnReset (Task.succeed ())


{-| Subscriptions for this module

    config : Config Msg
    config =
        Ptr.config "ptr"

    subscriptions : Model -> Sub Msg
    subscriptions model =
        Ptr.subscriptions PtrMsg config model.ptr

-}
subscriptions : (Msg -> msg) -> Config msg -> Model -> Sub msg
subscriptions mapper (Config config) (Model model) =
    case model.state of
        Internal.None ->
            Sub.none

        Internal.Start _ ->
            Sub.none

        Internal.Moving _ _ ->
            Sub.none

        Internal.Loading topPos elapsedTime ->
            if elapsedTime >= config.animationDuration then
                Sub.none
            else
                Sub.map mapper <| AnimationFrame.diffs OnUpdateFrame

        Internal.Ending topPos elapsedTime ->
            if elapsedTime >= config.animationDuration then
                Sub.none
            else
                Sub.map mapper <| AnimationFrame.diffs OnUpdateFrame



-- Internal


addPullToRefreshAttributes : (Msg -> msg) -> Model -> List (Html.Attribute msg)
addPullToRefreshAttributes mapper (Model model) =
    ([ Attributes.map mapper <| onMouseDown OnDown
     , Attributes.map mapper <| Touch.onStart (Touch.locate >> OnDown)
     , Attributes.map mapper <| onMouseUp OnUp
     , Attributes.map mapper <| Touch.onEnd (Touch.locate >> OnUp)
     ]
        ++ (if Internal.isStarted model.state then
                [ Attributes.map mapper <| onMouseMove OnMove
                , Attributes.map mapper <| Touch.onMove (Touch.locate >> OnMove)
                ]
            else
                []
           )
    )


onMouseDown : (Internal.Position -> Msg) -> Html.Attribute Msg
onMouseDown msg =
    Events.on "mousedown" (JD.map msg Internal.decodeMousePosition)


onMouseUp : (Internal.Position -> Msg) -> Html.Attribute Msg
onMouseUp msg =
    Events.on "mouseup" (JD.map msg Internal.decodeMousePosition)


onMouseMove : (Internal.Position -> Msg) -> Html.Attribute Msg
onMouseMove msg =
    Events.on "mousemove" (JD.map msg Internal.decodeMousePosition)


viewPullContent : (Msg -> msg) -> Config msg -> Model -> Float -> Html msg
viewPullContent mapper (Config config) (Model model) yPos =
    div
        [ style
            [ ( "position", "absolute" )
            , ( "margin", "0" )
            , ( "padding", "0" )
            , ( "overflow", "hidden" )
            , ( "left", "0" )
            , ( "top", "0" )
            , ( "height", (toString yPos) ++ "px" )
            , ( "right", "0" )
            ]
        ]
        (case model.state of
            Internal.None ->
                []

            Internal.Start _ ->
                [ defaultPullContent ]

            Internal.Moving _ _ ->
                [ if yPos < config.triggerDist then
                    config.pullContent
                  else
                    config.releaseContent
                ]

            Internal.Loading _ _ ->
                [ config.loadingContent ]

            Internal.Ending _ _ ->
                []
        )



-- Default contents


defaultStyles : List (Html.Attribute msg)
defaultStyles =
    [ style
        [ ( "text-align", "center" )
        , ( "margin", "auto" )
        , ( "padding", "20px" )
        ]
    ]


defaultPullContent : Html msg
defaultPullContent =
    div defaultStyles [ text "Pull to refresh" ]


defaultReleaseContent : Html msg
defaultReleaseContent =
    div defaultStyles [ text "Release to refresh" ]


defaultLoadingContent : Html msg
defaultLoadingContent =
    div defaultStyles [ text "Loading ..." ]