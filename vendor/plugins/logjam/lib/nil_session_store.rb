class NilSessionStore < ActionController::Session::AbstractStore
  def get_session(env, sid)
    raise NotImplementedError, "NilSessionStore: No session configured"
  end

  def set_session(env, sid, session_data)
    raise NotImplementedError, "NilSessionStore: No session configured"
  end
end

